import Foundation
import AVFoundation
import Combine

class ElevenLabsService: NSObject, ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var voices: [VoiceOption] = []

    private let apiKey: String
    private var audioPlayer: AVAudioPlayer?
    private var streamTask: URLSessionDataTask?
    private var streamDelegate: TTSStreamDelegate?

    // Streaming PCM state
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var pcmBuffer: Data = Data()
    private let pcmSampleRate: Double = 24000
    private let chunkThreshold = 48000 * 1 / 3 // ~0.33s worth of 16-bit 24kHz PCM

    var onPlaybackFinished: (() -> Void)?

    override init() {
        self.apiKey = ""
        super.init()
    }

    init(apiKey: String) {
        self.apiKey = apiKey
        super.init()
        setupStreamingEngine()
    }

    private func setupStreamingEngine() {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: pcmSampleRate, channels: 1, interleaved: false)!
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
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

    // MARK: - Streaming TTS

    func speak(text: String, voiceID: String, language: String = "vi") {
        guard !text.isEmpty else { return }
        stopSpeaking()
        DispatchQueue.main.async { self.isPlaying = true }

        let urlStr = "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)/stream"
        guard let url = URL(string: urlStr) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")

        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_multilingual_v2",
            "language_code": language,
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75,
                "style": 0.0,
                "use_speaker_boost": true
            ],
            "output_format": "pcm_24000"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // Start audio engine
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
            if !audioEngine.isRunning { try audioEngine.start() }
            playerNode.play()
        } catch {
            print("Audio engine start error: \(error)")
        }

        pcmBuffer = Data()
        let delegate = TTSStreamDelegate(service: self)
        streamDelegate = delegate
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.dataTask(with: request)
        streamTask = task
        task.resume()
    }

    func stopSpeaking() {
        streamTask?.cancel()
        streamTask = nil
        streamDelegate = nil
        playerNode.stop()
        pcmBuffer = Data()
        audioPlayer?.stop()
        audioPlayer = nil
        DispatchQueue.main.async { self.isPlaying = false }
    }

    // MARK: - PCM Streaming internals

    fileprivate func didReceivePCMData(_ data: Data) {
        pcmBuffer.append(data)
        // Play in chunks to reduce latency
        while pcmBuffer.count >= chunkThreshold {
            let chunk = pcmBuffer.prefix(chunkThreshold)
            pcmBuffer = pcmBuffer.dropFirst(chunkThreshold)
            scheduleChunk(Data(chunk))
        }
    }

    fileprivate func didFinishStream() {
        // Play remaining buffer
        if !pcmBuffer.isEmpty {
            scheduleChunk(pcmBuffer)
            pcmBuffer = Data()
        }
        // Wait for playback to finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.waitForPlaybackEnd()
        }
    }

    private func waitForPlaybackEnd() {
        if playerNode.isPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.waitForPlaybackEnd()
            }
        } else {
            DispatchQueue.main.async {
                self.isPlaying = false
                self.onPlaybackFinished?()
            }
        }
    }

    private func scheduleChunk(_ data: Data) {
        guard let buffer = makePCMBuffer(from: data) else { return }
        if !audioEngine.isRunning { try? audioEngine.start() }
        if !playerNode.isPlaying { playerNode.play() }
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func makePCMBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = UInt32(data.count / 2)
        guard frameCount > 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: pcmSampleRate, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            let int16 = raw.bindMemory(to: Int16.self)
            if let floats = buffer.floatChannelData?[0] {
                for i in 0..<Int(frameCount) {
                    floats[i] = Float(int16[i]) / 32768.0
                }
            }
        }
        return buffer
    }

    // MARK: - Preview

    func previewVoice(_ voice: VoiceOption) {
        guard let previewURL = voice.preview_url, let url = URL(string: previewURL) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data = data else { return }
            DispatchQueue.main.async {
                try? self?.audioPlayer = AVAudioPlayer(data: data)
                self?.audioPlayer?.play()
            }
        }.resume()
    }
}

// MARK: - Stream Delegate

private class TTSStreamDelegate: NSObject, URLSessionDataDelegate {
    weak var service: ElevenLabsService?
    init(service: ElevenLabsService) { self.service = service }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        service?.didReceivePCMData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil { service?.didFinishStream() }
        else { DispatchQueue.main.async { self.service?.isPlaying = false } }
    }
}
