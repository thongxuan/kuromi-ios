import Foundation
import AVFoundation
import AVFAudio

/// Relay service for streaming audio to remote relay server.
/// Uses shared AudioEngine for audio input - does NOT manage its own AVAudioEngine.
class AudioRelayService: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isPlayingTTS = false

    // Callbacks for UI
    var onReady: (() -> Void)?
    var onTranscript: ((String, Bool) -> Void)?
    var onAIText: ((String) -> Void)?
    var onTTSStart: (() -> Void)?
    var onTTSEnd: (() -> Void)?
    var onMicStop: (() -> Void)?
    var onDisconnected: (() -> Void)?

    private var gatewayURL = ""
    private var sttLanguage = "vi"
    private var ttsVoice = "NF"
    private var gatewayToken = ""
    private var textMode = false

    private var ws: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var audioPlayer: AVAudioPlayer?
    private var ttsBuffer = Data()
    var useSpeaker: Bool = false
    private var isReceivingTTS = false

    private var reconnectTimer: Timer?
    private var reconnectAttempts = 0
    private var isReconnecting = false
    private let bargeInThreshold: Float = 0.3
    private var didBargeIn: Bool = false

    // MARK: - Connect / Disconnect

    func connect(gatewayURL: String, language: String, voice: String, token: String = "", textMode: Bool = false) {
        self.gatewayURL = gatewayURL
        self.sttLanguage = language
        self.ttsVoice = voice
        self.gatewayToken = token
        self.textMode = textMode
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
        ws?.cancel()
        ws = nil
        // Keep isReconnecting = true until new socket is set up
        defer { isReconnecting = false }

        // Reset state on reconnect
        isPlayingTTS = false
        isReceivingTTS = false
        ttsBuffer = Data()
        audioPlayer?.stop()
        audioPlayer = nil

        isConnected = false
        urlSession = URLSession(configuration: .default, delegate: nil, delegateQueue: .main)
        ws = urlSession?.webSocketTask(with: wsURL)
        ws?.resume()
        receive()

        var startMsg: [String: String] = ["type": textMode ? "start_text" : "start", "language": sttLanguage, "voice": ttsVoice]
        if !gatewayToken.isEmpty { startMsg["token"] = gatewayToken }
        sendJSON(startMsg)
        print("[relay] connecting -> \(url)")
    }

    func disconnect() {
        ws?.cancel()
        ws = nil
        isConnected = false
    }

    func reconnect() {
        reconnectAttempts = 0
        doConnect()
    }

    func appDidBecomeActive() {
        guard !gatewayURL.isEmpty else { return }
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

    // MARK: - Audio Buffer Processing

    /// Called by AudioEngine in listening state with converted PCM buffer.
    func appendBuffer(_ buffer: AVAudioPCMBuffer, rms: Float) {
        let data = pcmData(from: buffer)
        guard !data.isEmpty else { return }

        // During TTS playback, check for barge-in
        if isPlayingTTS {
            if rms > bargeInThreshold && !didBargeIn {
                didBargeIn = true
                print("[relay] barge-in (level=\(rms))")
                sendJSON(["type": "barge_in"])
                sendBinary(data)
            }
        } else {
            sendBinary(data)
        }
    }

    /// Tell relay to stop processing current turn.
    func sendBargeIn() { sendJSON(["type": "barge_in"]) }

    func sendStopSignal() {
        sendJSON(["type": "stop"])
    }

    func sendTranscript(_ text: String) {
        sendJSON(["type": "transcript", "text": text])
    }

    /// Reset barge-in flag for new TTS.
    func resetBargeIn() {
        didBargeIn = false
    }

    // MARK: - Receive

    private func receive() {
        let capturedWs = ws  // capture current socket — ignore callbacks from old sockets
        ws?.receive { [weak self] result in
            guard let self = self, self.ws === capturedWs else { return }  // stale callback
            switch result {
            case .success(let msg):
                switch msg {
                case .string(let text): self.handleJSON(text)
                case .data(let data): self.handleBinary(data)
                @unknown default: break
                }
                self.receive()
            case .failure(let err):
                print("[relay] disconnected: \(err.localizedDescription)")
                DispatchQueue.main.async {
                    self.isConnected = false
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
                let text = json["text"] as? String ?? ""
                self.onAIText?(text)

            case "tts_start":
                self.ttsBuffer = Data()
                self.isReceivingTTS = true
                self.isPlayingTTS = true
                self.didBargeIn = false
                self.onTTSStart?()

            case "tts_end":
                self.isReceivingTTS = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.playTTSBuffer()
                }

            case "mic_stop":
                self.onMicStop?()

            case "tts_abort":
                self.isReceivingTTS = false
                self.isPlayingTTS = false
                self.audioPlayer?.stop()
                self.audioPlayer = nil
                self.ttsBuffer = Data()
                self.onTTSEnd?()

            default:
                break
            }
        }
    }

    private func handleBinary(_ data: Data) {
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
        do {
            audioPlayer = try AVAudioPlayer(data: ttsBuffer)
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

    private func pcmData(from buffer: AVAudioPCMBuffer) -> Data {
        guard let ch = buffer.int16ChannelData else { return Data() }
        return Data(bytes: ch[0], count: Int(buffer.frameLength) * 2)
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
