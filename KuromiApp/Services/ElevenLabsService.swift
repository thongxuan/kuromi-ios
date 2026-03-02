import Foundation
import AVFoundation
import Combine

class ElevenLabsService: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var voices: [VoiceOption] = []

    private let apiKey: String
    private let audioService = AudioService.shared
    private var currentDataTask: URLSessionDataTask?

    var onPlaybackFinished: (() -> Void)?

    init(apiKey: String) {
        self.apiKey = apiKey
    }

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

        DispatchQueue.main.async {
            self.voices = voicesResponse.voices
        }
        return voicesResponse.voices
    }

    // MARK: - Text to Speech

    func speak(text: String, voiceID: String) {
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
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.75
            ],
            "output_format": "pcm_24000"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default, delegate: StreamDelegate(service: self), delegateQueue: nil)
        let task = session.dataTask(with: request)
        currentDataTask = task
        task.resume()
    }

    func stopSpeaking() {
        currentDataTask?.cancel()
        currentDataTask = nil
        audioService.stopPlayback()
        DispatchQueue.main.async { self.isPlaying = false }
    }

    // MARK: - Preview Voice

    func previewVoice(_ voice: VoiceOption) {
        guard let previewURL = voice.preview_url, let url = URL(string: previewURL) else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data {
                self?.audioService.playAudioData(data)
            }
        }.resume()
    }

    fileprivate func didReceiveData(_ data: Data) {
        audioService.playAudioData(data)
    }

    fileprivate func didFinish() {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.onPlaybackFinished?()
        }
    }
}

private class StreamDelegate: NSObject, URLSessionDataDelegate {
    weak var service: ElevenLabsService?

    init(service: ElevenLabsService) {
        self.service = service
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        service?.didReceiveData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil {
            service?.didFinish()
        }
    }
}
