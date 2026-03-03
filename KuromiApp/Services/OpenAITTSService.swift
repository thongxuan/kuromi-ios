import Foundation
import AVFoundation

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
        print("OpenAI TTS speak: apiKey=\(apiKey.prefix(8))... voice=\(voice) text=\(text.prefix(30))")
        guard !text.isEmpty else { print("TTS skipped: text empty"); return }
        guard !apiKey.isEmpty else { print("TTS skipped: apiKey empty"); return }
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
