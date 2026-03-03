import Foundation
import AVFoundation

class STTService: NSObject, ObservableObject {
    @Published var transcript: String = ""
    @Published var isConnected: Bool = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private let apiKey: String
    private let language: String

    var onTranscript: ((String, Bool) -> Void)? // text, isFinal
    var onUtteranceEnd: (() -> Void)?

    init(apiKey: String, language: String = "vi") {
        self.language = language
        self.apiKey = apiKey
        super.init()
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func connect() {
        var urlComponents = URLComponents()
        urlComponents.scheme = "wss"
        urlComponents.host = "api.deepgram.com"
        urlComponents.path = "/v1/listen"
        urlComponents.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "16000"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "model", value: "nova-2"),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "vad_events", value: "true"),
            URLQueryItem(name: "utterance_end_ms", value: "1500"),
            URLQueryItem(name: "endpointing", value: "500")
        ]
        guard let url = urlComponents.url else { return }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = urlSession.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        receiveMessages()
    }

    func disconnect() {
        // Send CloseStream
        let closeMsg = "{\"type\":\"CloseStream\"}"
        webSocketTask?.send(.string(closeMsg)) { _ in }
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.transcript = ""
        }
    }

    func sendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isConnected else { return }

        // Convert to 16kHz 16-bit PCM
        guard let resampled = resample(buffer: buffer, toSampleRate: 16000),
              let pcmData = AudioService.convertBufferToInt16Data(resampled) else { return }

        webSocketTask?.send(.data(pcmData)) { error in
            if let error = error {
                print("Deepgram send error: \(error)")
            }
        }
    }

    private func resample(buffer: AVAudioPCMBuffer, toSampleRate targetRate: Double) -> AVAudioPCMBuffer? {
        let inputFormat = buffer.format
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: targetRate,
                                               channels: 1,
                                               interleaved: false),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else { return nil }

        let ratio = targetRate / inputFormat.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCapacity) else { return nil }

        var error: NSError?
        var inputDone = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            outStatus.pointee = .haveData
            inputDone = true
            return buffer
        }
        return error == nil ? outputBuffer : nil
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self.handleTranscript(text)
                }
                self.receiveMessages()
            case .failure(let error):
                print("Deepgram receive error: \(error)")
                DispatchQueue.main.async { self.isConnected = false }
            }
        }
    }

    private func handleTranscript(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        // Handle UtteranceEnd event
        if let type = obj["type"] as? String, type == "UtteranceEnd" {
            DispatchQueue.main.async { self.onUtteranceEnd?() }
            return
        }

        guard let channel = obj["channel"] as? [String: Any],
              let alternatives = channel["alternatives"] as? [[String: Any]],
              let first = alternatives.first,
              let transcript = first["transcript"] as? String,
              !transcript.isEmpty else { return }

        let isFinal = obj["is_final"] as? Bool ?? false

        DispatchQueue.main.async {
            self.transcript = transcript
            self.onTranscript?(transcript, isFinal)
        }
    }
}

extension STTService: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async { self.isConnected = true }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        DispatchQueue.main.async { self.isConnected = false }
    }
}
