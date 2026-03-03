import Foundation
import AVFoundation
import Combine

enum ChatState: Equatable {
    case connecting
    case idle
    case userSpeaking
    case aiSpeaking
    case error(String)
}

class ChatViewModel: ObservableObject {
    @Published var chatState: ChatState = .connecting
    @Published var messages: [Message] = []
    @Published var currentTranscript: String = ""
    @Published var inputLevel: Float = 0.0
    @Published var isToggleEnabled: Bool = false
    @Published var currentAIResponse: String = ""

    private let audioService = AudioService.shared
    private var gatewayService = GatewayService()
    private var deepgramService: DeepgramService?
    private var elevenLabsService: ElevenLabsService?
    private var wakeWordService = WakeWordService()

    private var settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var pendingWakeInput: String?
    private var connectTimer: Timer?
    private var silenceTimer: Timer?
    private var lastMeaningfulTranscript: String = ""
    private var transcriptStableCount: Int = 0
    @Published var showReconnectButton: Bool = false

    init() {
        settings = AppSettings.load()!
        setupServices()
    }

    private func setupServices() {
        deepgramService = DeepgramService(apiKey: settings.deepgramAPIKey, language: settings.sttLanguage)
        elevenLabsService = ElevenLabsService(apiKey: settings.elevenLabsAPIKey)

        // Gateway
        gatewayService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .connected:
                    self.chatState = .idle
                    self.isToggleEnabled = true
                    self.showReconnectButton = false
                    self.connectTimer?.invalidate()
                    // Handle pending wake input
                    if let wakeInput = self.pendingWakeInput {
                        self.pendingWakeInput = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.sendTextToGateway(wakeInput)
                        }
                    }
                case .connecting:
                    self.chatState = .connecting
                    self.isToggleEnabled = false
                case .error(let msg):
                    self.chatState = .error(msg)
                    self.isToggleEnabled = false
                case .disconnected:
                    self.chatState = .connecting
                    self.isToggleEnabled = false
                }
            }
            .store(in: &cancellables)

        gatewayService.onResponse = { [weak self] text in
            DispatchQueue.main.async { self?.currentAIResponse = text }
        }
        gatewayService.onDelta = { [weak self] delta in
            DispatchQueue.main.async {
                self?.currentAIResponse += delta
            }
        }
        gatewayService.onResponseComplete = { [weak self] in
            self?.handleGatewayResponseComplete()
        }

        // Deepgram transcript
        deepgramService?.onTranscript = { [weak self] text, isFinal in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentTranscript = text

                // Chỉ reset timer nếu text thay đổi đáng kể
                // (tránh tiếng ồn làm timer reset liên tục)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let hasNewContent = trimmed.count > self.lastMeaningfulTranscript.count + 2
                if hasNewContent {
                    self.lastMeaningfulTranscript = trimmed
                    self.resetSilenceTimer()
                }
            }
        }

        // Auto-finalize khi Deepgram detect hết câu
        deepgramService?.onUtteranceEnd = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, case .userSpeaking = self.chatState else { return }
                self.silenceTimer?.invalidate()
                if !self.currentTranscript.isEmpty {
                    self.finalizeSpeech(self.currentTranscript)
                }
            }
        }

        // ElevenLabs playback finished → tự động nghe lại
        elevenLabsService?.onPlaybackFinished = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isToggleEnabled {
                    self.startUserSpeaking()
                } else {
                    self.chatState = .idle
                }
            }
        }

        // Audio level + auto-interrupt khi AI đang nói
        audioService.$inputLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self = self else { return }
                self.inputLevel = level

            }
            .store(in: &cancellables)

        // Wake word
        wakeWordService.wakeWord = settings.wakeWord
        wakeWordService.onWakeWordDetected = { [weak self] phrase in
            self?.handleWakeWord(phrase)
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        connectWithTimeout(to: settings.gatewayURL)
        setupWakeWordListening()
    }

    func reconnect() {
        showReconnectButton = false
        connectWithTimeout(to: settings.gatewayURL)
    }

    private func connectWithTimeout(to url: String) {
        showReconnectButton = false
        gatewayService.connect(to: url, token: settings.gatewayToken)
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if case .connecting = self.chatState {
                    self.showReconnectButton = true
                }
            }
        }
    }

    func onDisappear() {
        stopUserSpeaking()
        gatewayService.disconnect()
        wakeWordService.stopListening()
    }

    private func setupWakeWordListening() {
        wakeWordService.requestPermission { [weak self] granted in
            if granted {
                // Wake word uses its own engine; we don't share with deepgram here
                // In production, you'd manage audio session carefully
            }
        }
    }

    // MARK: - Toggle

    func toggleSpeaking() {
        switch chatState {
        case .idle, .aiSpeaking:
            // Nếu AI đang nói thì ngắt luôn và bắt đầu nghe
            if case .aiSpeaking = chatState {
                elevenLabsService?.stopSpeaking()
            }
            startUserSpeaking()
        case .userSpeaking:
            stopUserSpeaking()
        default:
            break
        }
    }

    // MARK: - User Speaking

    private func resetSilenceTimer() {
        guard case .userSpeaking = chatState else { return }
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self = self, case .userSpeaking = self.chatState else { return }
            if !self.currentTranscript.isEmpty {
                self.finalizeSpeech(self.currentTranscript)
            }
        }
    }

    private func startUserSpeaking() {
        chatState = .userSpeaking
        currentTranscript = ""
        lastMeaningfulTranscript = ""
        deepgramService?.connect()

        audioService.startRecording { [weak self] buffer in
            self?.deepgramService?.sendAudioBuffer(buffer)
        }
    }

    private func stopUserSpeaking() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioService.stopRecording()
        deepgramService?.disconnect()

        if !currentTranscript.isEmpty {
            finalizeSpeech(currentTranscript)
        } else {
            chatState = .idle
        }
    }

    private func finalizeSpeech(_ text: String) {
        let msg = Message(role: .user, text: text)
        messages.append(msg)
        currentTranscript = ""
        audioService.stopRecording()
        deepgramService?.disconnect()
        sendTextToGateway(text)
    }

    // MARK: - Gateway

    private func sendTextToGateway(_ text: String) {
        chatState = .idle // wait for AI response
        gatewayService.sendMessage(text)
    }

    private func handleGatewayResponseComplete() {
        let text = currentAIResponse
        guard !text.isEmpty else { return }
        currentAIResponse = ""
        let msg = Message(role: .assistant, text: text)
        messages.append(msg)
        chatState = .aiSpeaking
        let voiceID = settings.selectedVoiceID.isEmpty ? "21m00Tcm4TlvDq8ikWAM" : settings.selectedVoiceID
        elevenLabsService?.speak(text: text, voiceID: voiceID, language: settings.sttLanguage)
    }

    // MARK: - AI Interrupt

    private func interruptAI() {
        elevenLabsService?.stopSpeaking()
        chatState = .idle
    }

    // MARK: - Wake Word

    private func handleWakeWord(_ phrase: String) {
        DispatchQueue.main.async {
            // Stop any current activity
            self.elevenLabsService?.stopSpeaking()
            self.audioService.stopRecording()
            self.deepgramService?.disconnect()

            // If not connected yet, store for later
            if case .connected = self.gatewayService.state {
                self.sendTextToGateway(phrase)
            } else {
                self.pendingWakeInput = phrase
                self.gatewayService.connect(to: self.settings.gatewayURL)
            }
        }
    }

    // MARK: - Settings

    func reloadSettings() {
        guard let newSettings = AppSettings.load() else { return }
        settings = newSettings
        deepgramService = DeepgramService(apiKey: newSettings.deepgramAPIKey, language: newSettings.sttLanguage)
        elevenLabsService = ElevenLabsService(apiKey: newSettings.elevenLabsAPIKey)
        elevenLabsService?.onPlaybackFinished = { [weak self] in
            DispatchQueue.main.async { self?.chatState = .idle }
        }
        deepgramService?.onTranscript = { [weak self] text, isFinal in
            DispatchQueue.main.async {
                self?.currentTranscript = text
                if isFinal && !text.isEmpty { self?.finalizeSpeech(text) }
            }
        }
        wakeWordService.wakeWord = newSettings.wakeWord
        gatewayService.disconnect()
        gatewayService.connect(to: newSettings.gatewayURL)
    }
}
