import Foundation
import AVFoundation

/// iOS chỉ làm 1 việc: stream PCM audio lên relay /audio
/// Relay tự lo: STT, silence detection, gateway, TTS
class AudioRelayService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isListening = false
    @Published var isPlayingTTS = false

    // Callbacks cho UI
    var onReady: (() -> Void)?
    var onTranscript: ((String, Bool) -> Void)?
    var onAIText: ((String) -> Void)?
    var onTTSStart: (() -> Void)?
    var onTTSEnd: (() -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onMicStop: (() -> Void)?
    var onDisconnected: (() -> Void)?

    private var gatewayURL = ""
    private var sttLanguage = "vi"
    private var ttsVoice = "NF"
    private var gatewayToken = ""

    private var ws: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayer?
    private var ttsBuffer = Data()
    private var isReceivingTTS = false

    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private var isReconnecting = false
    private let bargeInThreshold: Float = 0.2
    private var didBargeIn: Bool = false  // prevent repeated barge-in for same TTS

    // MARK: - Connect / Disconnect

    func connect(gatewayURL: String, language: String, voice: String, token: String = "") {
        self.gatewayURL = gatewayURL
        self.sttLanguage = language
        self.ttsVoice = voice
        self.gatewayToken = token
        reconnectAttempts = 0
        reconnectTimer?.invalidate()
        doConnect()
    }

    private func doConnect() {
        var url = gatewayURL
        if url.hasSuffix("/") { url = String(url.dropLast()) }
        url += "/audio"
        guard let wsURL = URL(string: url) else { return }

        isReconnecting = true
        ws?.cancel(); ws = nil
        isReconnecting = false

        // Reset state on reconnect
        isPlayingTTS = false
        isReceivingTTS = false
        ttsBuffer = Data()
        audioPlayer?.stop(); audioPlayer = nil

        urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        ws = urlSession?.webSocketTask(with: wsURL)
        ws?.resume()
        isConnected = true
        receive()

        var startMsg: [String: String] = ["type": "start", "language": sttLanguage, "voice": ttsVoice]
        if !gatewayToken.isEmpty { startMsg["token"] = gatewayToken }
        sendJSON(startMsg)
        print("[relay] connected → \(url)")
    }

    func disconnect() {
        stopMic()
        ws?.cancel(); ws = nil
        isConnected = false
    }

    func reconnect() {
        reconnectAttempts = 0
        stopMic()
        doConnect()
    }

    func appDidBecomeActive() {
        guard !gatewayURL.isEmpty, !isConnected else { return }
        reconnectAttempts = 0
        reconnectTimer?.invalidate()
        doConnect()
    }

    private func scheduleReconnect() {
        guard !gatewayURL.isEmpty else { return }
        reconnectTimer?.invalidate()
        reconnectAttempts += 1
        let delay = min(Double(reconnectAttempts) * 2.0, 30.0)
        print("[relay] reconnect in \(delay)s (attempt \(reconnectAttempts))")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self, !self.isConnected else { return }
            self.doConnect()
        }
    }

    // MARK: - Mic

    func startMic() {
        guard !isListening else { return }
        // Use .measurement mode — disables AGC/noise cancellation so mic is more sensitive
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers])
        try? session.setActive(true)
        let inputNode = audioEngine.inputNode
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self, let converted = self.convertBuffer(buffer, to: format) else { return }
            let level = self.computeRMS(from: converted)
            DispatchQueue.main.async { self.onAudioLevel?(level) }
            let data = self.pcmData(from: converted)
            guard !data.isEmpty else { return }
            if self.isPlayingTTS {
                if level > self.bargeInThreshold && !self.didBargeIn {
                    self.didBargeIn = true
                    print("[relay] barge-in (level=\(level))")
                    self.sendJSON(["type": "barge_in"])
                    self.sendBinary(data)
                }
            } else {
                self.sendBinary(data)
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
        print("[relay] mic stopped")
    }

    // MARK: - Receive

    private func receive() {
        ws?.receive { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let text): self.handleJSON(text)
                case .data(let data):   self.handleBinary(data)
                @unknown default: break
                }
                self.receive()
            case .failure(let err):
                guard !self.isReconnecting else { return }
                print("[relay] disconnected: \(err.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isListening = false
                    self.onDisconnected?()
                    self.scheduleReconnect()
                }
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
                self.isConnected = true
                self.onReady?()
            case "transcript":
                let t = json["text"] as? String ?? ""
                let final = json["is_final"] as? Bool ?? false
                self.onTranscript?(t, final)
            case "ai_text":
                self.onAIText?(json["text"] as? String ?? "")
            case "tts_start":
                self.ttsBuffer = Data()
                self.isReceivingTTS = true
                self.isPlayingTTS = true
                self.didBargeIn = false  // reset for new TTS
                self.onTTSStart?()
            case "tts_end":
                self.isReceivingTTS = false
                self.playTTSBuffer()
            case "mic_stop":
                self.stopMic()
                self.onMicStop?()
            case "tts_abort":
                self.isReceivingTTS = false
                self.isPlayingTTS = false
                self.audioPlayer?.stop()
                self.audioPlayer = nil
                self.ttsBuffer = Data()
                self.onTTSEnd?()
            default: break
            }
        }
    }

    private func handleBinary(_ data: Data) {
        DispatchQueue.main.async {
            if self.isReceivingTTS { self.ttsBuffer.append(data) }
        }
    }

    // MARK: - TTS Playback

    private func playTTSBuffer() {
        guard !ttsBuffer.isEmpty else { isPlayingTTS = false; onTTSEnd?(); return }
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kuromi_tts_\(UUID().uuidString).wav")
        do {
            try ttsBuffer.write(to: tmp)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
            try? session.overrideOutputAudioPort(.speaker)
            audioPlayer = try AVAudioPlayer(contentsOf: tmp)
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

    private func sendBinary(_ data: Data) { ws?.send(.data(data)) { _ in } }

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frames = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        var filled = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if !filled { filled = true; status.pointee = .haveData; return buffer }
            status.pointee = .noDataNow; return nil
        }
        return err == nil ? out : nil
    }

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data {
        guard let ch = buffer.int16ChannelData else { return Data() }
        return Data(bytes: ch[0], count: Int(buffer.frameLength) * 2)
    }

    private func computeRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.int16ChannelData, buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let s = Float(ch[0][i]) / 32768.0
            sum += s * s
        }
        return min(sqrt(sum / Float(buffer.frameLength)) * 8.0, 1.0)
    }
}

extension AudioRelayService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
        DispatchQueue.main.async {
            self.isPlayingTTS = false
            self.onTTSEnd?()
        }
    }
}
