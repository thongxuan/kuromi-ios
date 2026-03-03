import Foundation
import AVFoundation

/// Kết nối tới audio relay server, stream mic audio lên, nhận TTS audio về
class AudioRelayService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isListening = false
    @Published var isPlayingTTS = false

    var onTranscript: ((String, Bool) -> Void)?
    var onAIText: ((String) -> Void)?
    var onTTSStart: (() -> Void)?
    var onTTSEnd: (() -> Void)?
    var onReady: (() -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onMicStop: (() -> Void)?
    var onUtteranceEnd: (() -> Void)?

    private var ws: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    private var ttsBuffer = Data()
    private var isReceivingTTS = false
    private var micFormat: AVAudioFormat?

    // MARK: - Connect
    func connect(gatewayURL: String, language: String, voice: String) {
        // Derive audio relay URL: append /audio to gateway URL
        var relayURL = gatewayURL
        if relayURL.hasSuffix("/") { relayURL = String(relayURL.dropLast()) }
        relayURL += "/audio"
        guard let url = URL(string: relayURL) else { return }

        urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        ws = urlSession?.webSocketTask(with: url)
        ws?.resume()
        isConnected = true
        receive()

        // Send start config
        sendJSON(["type": "start", "language": language, "voice": voice])
        print("[relay] connected to \(relayURL)")
    }

    func disconnect() {
        stopMic()
        ws?.cancel()
        ws = nil
        isConnected = false
    }

    // MARK: - Mic
    func startMic() {
        guard !isListening else { return }
        let inputNode = audioEngine.inputNode
        // 16kHz mono linear16
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        micFormat = format
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        // Install converter tap
        let bufferSize: AVAudioFrameCount = 1024
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self, let converted = self.convertBuffer(buffer, to: format) else { return }
            let data = self.pcmData(from: converted)
            if !data.isEmpty {
                self.sendBinary(data)
                // Compute RMS audio level for orb animation
                let level = self.computeRMS(from: converted)
                DispatchQueue.main.async { self.onAudioLevel?(level) }
            }
        }
        do {
            try audioEngine.start()
            isListening = true
            print("[relay] mic started")
        } catch {
            print("[relay] mic error: \(error)")
        }
    }

    func stopMic() {
        guard isListening else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isListening = false
        sendJSON(["type": "stop"])
    }

    // MARK: - Receive
    private func receive() {
        ws?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleJSON(text)
                case .data(let data):
                    self.handleAudio(data)
                @unknown default: break
                }
                self.receive() // loop
            case .failure(let err):
                print("[relay] receive error: \(err)")
                DispatchQueue.main.async { self.isConnected = false }
            }
        }
    }

    private func handleJSON(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        DispatchQueue.main.async {
            switch type {
            case "ready":
                self.onReady?()
            case "transcript":
                let t = json["text"] as? String ?? ""
                let isFinal = json["is_final"] as? Bool ?? false
                self.onTranscript?(t, isFinal)
            case "ai_text":
                let t = json["text"] as? String ?? ""
                self.onAIText?(t)
            case "tts_start":
                self.ttsBuffer = Data()
                self.isReceivingTTS = true
                self.isPlayingTTS = true
                self.onTTSStart?()
            case "tts_end":
                self.isReceivingTTS = false
                self.playTTSBuffer()
            case "mic_stop":
                self.stopMic()
                self.onMicStop?()
            case "utterance_end":
                self.onUtteranceEnd?()
            default: break
            }
        }
    }

    private func handleAudio(_ data: Data) {
        DispatchQueue.main.async {
            if self.isReceivingTTS {
                self.ttsBuffer.append(data)
            }
        }
    }

    // MARK: - TTS Playback
    private func playTTSBuffer() {
        guard !ttsBuffer.isEmpty else {
            isPlayingTTS = false
            onTTSEnd?()
            return
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuromi_relay_\(UUID().uuidString).mp3")
        do {
            try ttsBuffer.write(to: tempURL)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            try? session.overrideOutputAudioPort(.speaker)
            audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
            audioPlayer?.delegate = self
            audioPlayer?.volume = 1.0
            audioPlayer?.play()
        } catch {
            print("[relay] playback error: \(error)")
            isPlayingTTS = false
            onTTSEnd?()
        }
    }

    // MARK: - Helpers
    private func sendJSON(_ dict: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        ws?.send(.string(str)) { _ in }
    }

    private func sendBinary(_ data: Data) {
        ws?.send(.data(data)) { _ in }
    }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        var error: NSError?
        var filled = false
        converter.convert(to: converted, error: &error) { _, outStatus in
            if !filled {
                filled = true
                outStatus.pointee = .haveData
                return buffer
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        return error == nil ? converted : nil
    }

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data {
        guard let int16 = buffer.int16ChannelData else { return Data() }
        let frameLength = Int(buffer.frameLength)
        return Data(bytes: int16[0], count: frameLength * 2)
    }

    private func computeRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let int16 = buffer.int16ChannelData else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = Float(int16[0][i]) / 32768.0
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Normalize: typical speech RMS ~0.01-0.1, scale to 0-1
        return min(rms * 8.0, 1.0)
    }
}

extension AudioRelayService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlayingTTS = false
            self.onTTSEnd?()
        }
    }
}
