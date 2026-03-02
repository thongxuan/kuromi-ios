import Foundation
import AVFoundation
import Combine

class ElevenLabsService: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var voices: [VoiceOption] = []

    private let apiKey: String
    private let audioService = AudioService.shared
    private var currentDataTask: URLSessionDataTask?
    private var audioPlayer: AVAudioPlayer?

    var onPlaybackFinished: (() -> Void)?

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    // MARK: - Premade voices

    static let premadeVoices: [VoiceOption] = [
        VoiceOption(voice_id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", labels: ["accent": "american", "gender": "female"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "AZnzlk1XvdvUeBnXmlld", name: "Domi", labels: ["accent": "american", "gender": "female"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "EXAVITQu4vr4xnSDxMaL", name: "Bella", labels: ["accent": "american", "gender": "female"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "ErXwobaYiN019PkySvjV", name: "Antoni", labels: ["accent": "american", "gender": "male"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "MF3mGyEYCl7XYWbV9V6O", name: "Elli", labels: ["accent": "american", "gender": "female"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "TxGEqnHWrfWFTfGW9XjX", name: "Josh", labels: ["accent": "american", "gender": "male"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "VR6AewLTigWG4xSOukaG", name: "Arnold", labels: ["accent": "american", "gender": "male"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "pNInz6obpgDQGcFmaJgB", name: "Adam", labels: ["accent": "american", "gender": "male"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "yoZ06aMxZJJ28mfd3POQ", name: "Sam", labels: ["accent": "american", "gender": "male"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "XB0fDUnXU5powFXDhCwa", name: "Charlotte", labels: ["accent": "english-swedish", "gender": "female"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice", labels: ["accent": "british", "gender": "female"], preview_url: nil, category: "premade"),
        VoiceOption(voice_id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel", labels: ["accent": "british", "gender": "male"], preview_url: nil, category: "premade"),
    ]

    // MARK: - Fetch Voices

    func fetchVoices() async throws -> [VoiceOption] {
        let url = URL(string: "https://api.elevenlabs.io/v1/voices")!
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Check HTTP status
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "ElevenLabs", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }

        let decoder = JSONDecoder()
        let voicesResponse = try decoder.decode(VoicesResponse.self, from: data)

        // Merge với premade voices mặc định
        var allVoices = voicesResponse.voices
        let accountIds = Set(allVoices.map { $0.voice_id })
        for v in ElevenLabsService.premadeVoices where !accountIds.contains(v.voice_id) {
            allVoices.append(v)
        }

        DispatchQueue.main.async {
            self.voices = allVoices
        }
        return allVoices
    }

    // MARK: - Text to Speech

    func speak(text: String, voiceID: String) {
        guard !text.isEmpty else { return }
        stopSpeaking()
        DispatchQueue.main.async { self.isPlaying = true }

        let urlStr = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                print("ElevenLabs TTS error: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { self.isPlaying = false }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("ElevenLabs TTS HTTP \(http.statusCode): \(body)")
                DispatchQueue.main.async { self.isPlaying = false }
                return
            }
            self.playMP3Data(data)
        }
        currentDataTask = task
        task.resume()
    }

    private func playMP3Data(_ data: Data) {
        do {
            // Configure audio session for playback
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)

            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            DispatchQueue.main.async { self.isPlaying = true }
        } catch {
            print("AVAudioPlayer error: \(error)")
            DispatchQueue.main.async {
                self.isPlaying = false
                self.onPlaybackFinished?()
            }
        }
    }

    func stopSpeaking() {
        currentDataTask?.cancel()
        currentDataTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        audioService.stopPlayback()
        DispatchQueue.main.async { self.isPlaying = false }
    }

    // MARK: - Preview Voice

    func previewVoice(_ voice: VoiceOption) {
        guard let previewURL = voice.preview_url, let url = URL(string: previewURL) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data { self?.playMP3Data(data) }
        }.resume()
    }
}

extension ElevenLabsService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.onPlaybackFinished?()
        }
    }
}
