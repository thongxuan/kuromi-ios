import Foundation
import AVFoundation
import Combine

class ElevenLabsService: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var voices: [VoiceOption] = []

    private let apiKey: String
    private var audioPlayer: AVAudioPlayer?
    private var dataTask: URLSessionDataTask?

    var onPlaybackFinished: (() -> Void)?

    override init() {
        self.apiKey = ""
        super.init()
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
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
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "ElevenLabs", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        let voicesResponse = try JSONDecoder().decode(VoicesResponse.self, from: data)
        var allVoices = voicesResponse.voices
        let accountIds = Set(allVoices.map { $0.voice_id })
        for v in ElevenLabsService.premadeVoices where !accountIds.contains(v.voice_id) {
            allVoices.append(v)
        }
        DispatchQueue.main.async { self.voices = allVoices }
        return allVoices
    }

    // MARK: - TTS

    func speak(text: String, voiceID: String, language: String = "vi") {
        guard !text.isEmpty else { return }
        stopSpeaking()
        DispatchQueue.main.async { self.isPlaying = true }

        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "voice_settings": ["stability": 0.5, "similarity_boost": 0.75, "use_speaker_boost": true]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                print("ElevenLabs error: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { self.isPlaying = false }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("ElevenLabs HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
                DispatchQueue.main.async { self.isPlaying = false }
                return
            }
            self.playAudioData(data)
        }
        dataTask = task
        task.resume()
    }

    private func playAudioData(_ data: Data) {
        // Write to temp file để AVAudioPlayer đọc ổn định hơn
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("kuromi_tts_\(UUID().uuidString).mp3")
        do {
            try data.write(to: tempURL)
        } catch {
            print("Failed to write temp audio: \(error)")
            DispatchQueue.main.async { self.isPlaying = false }
            return
        }

        DispatchQueue.main.async {
            do {
                // Giữ .playAndRecord — coexist với engine mic
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .voiceChat,
                                        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try session.setActive(true)
                self.audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.volume = 1.0
                self.audioPlayer?.prepareToPlay()
                let success = self.audioPlayer?.play() ?? false
                print("TTS play: \(success), duration: \(self.audioPlayer?.duration ?? 0)s")
                self.isPlaying = true
            } catch {
                print("AVAudioPlayer error: \(error)")
                self.isPlaying = false
                self.onPlaybackFinished?()
            }
        }
    }

    func stopSpeaking() {
        dataTask?.cancel()
        dataTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        DispatchQueue.main.async { self.isPlaying = false }
    }

    // MARK: - Preview

    func previewVoice(_ voice: VoiceOption) {
        guard let previewURL = voice.preview_url, let url = URL(string: previewURL) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data else { return }
            self?.playAudioData(data)
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

class OpenAITTSService: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false

    private let apiKey: String
    private var audioPlayer: AVAudioPlayer?
    private var dataTask: URLSessionDataTask?

    var onPlaybackFinished: (() -> Void)?

    // Danh sách voices OpenAI
    static let voices = ["alloy", "ash", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer"]
    static let defaultVoice = "nova"

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    // MARK: - TTS

    func speak(text: String, voice: String = defaultVoice) {
        guard !text.isEmpty, !apiKey.isEmpty else { return }
        stopSpeaking()
        DispatchQueue.main.async { self.isPlaying = true }

        guard let url = URL(string: "https://api.openai.com/v1/audio/speech") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "voice": voice,
            "input": text,
            "response_format": "mp3"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                print("OpenAI TTS error: \(error?.localizedDescription ?? "unknown")")
                DispatchQueue.main.async { self.isPlaying = false; self.onPlaybackFinished?() }
                return
            }
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                print("OpenAI TTS HTTP \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
                DispatchQueue.main.async { self.isPlaying = false; self.onPlaybackFinished?() }
                return
            }
            self.playAudioData(data)
        }
        dataTask = task
        task.resume()
    }

    private func playAudioData(_ data: Data) {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuromi_openai_tts_\(UUID().uuidString).mp3")
        do {
            try data.write(to: tempURL)
        } catch {
            print("Failed to write temp audio: \(error)")
            DispatchQueue.main.async { self.isPlaying = false; self.onPlaybackFinished?() }
            return
        }

        DispatchQueue.main.async {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .voiceChat,
                                        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
                try session.setActive(true)
                self.audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                self.audioPlayer?.delegate = self
                self.audioPlayer?.volume = 1.0
                self.audioPlayer?.prepareToPlay()
                let ok = self.audioPlayer?.play() ?? false
                print("OpenAI TTS play: \(ok), duration: \(self.audioPlayer?.duration ?? 0)s")
                self.isPlaying = true
            } catch {
                print("AVAudioPlayer error: \(error)")
                self.isPlaying = false
                self.onPlaybackFinished?()
            }
        }
    }

    func stopSpeaking() {
        dataTask?.cancel()
        dataTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        DispatchQueue.main.async { self.isPlaying = false }
    }
}

extension OpenAITTSService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.onPlaybackFinished?()
        }
    }
}
