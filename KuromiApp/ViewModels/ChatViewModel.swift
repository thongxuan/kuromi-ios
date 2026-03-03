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
    private var deepgramService: STTService?
    private var ttsService: TTSService?
    private var wakeWordService = WakeWordService()

    private var settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var pendingWakeInput: String?
    private var connectTimer: Timer?
    private var silenceTimer: Timer?
    private var lastMeaningfulTranscript: String = ""
    private var transcriptStableCount: Int = 0
    private var accumulatedText: String = ""
    @Published var showReconnectButton: Bool = false
    @Published var isLoudSpeaker: Bool = true

    init() {
        settings = AppSettings.load()!
        setupServices()
    }

    private func setupServices() {
        deepgramService = STTService(apiKey: settings.deepgramAPIKey, language: settings.sttLanguage)
        ttsService = TTSService(apiKey: settings.ttsAPIKey)
        ttsService?.openAIKey = settings.openAIKey

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

                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

                if isFinal {
                    // Deepgram hay gửi is_final=true với text rỗng sau silence → bỏ qua
                    guard !trimmed.isEmpty else { return }
                    self.accumulatedText = self.accumulatedText.isEmpty
                        ? trimmed
                        : self.accumulatedText + " " + trimmed
                    self.currentTranscript = self.accumulatedText
                } else {
                    // Interim: hiện accumulated + đoạn đang nói
                    self.currentTranscript = self.accumulatedText.isEmpty
                        ? trimmed
                        : (trimmed.isEmpty ? self.accumulatedText : self.accumulatedText + " " + trimmed)
                }

                let hasNewContent = self.currentTranscript.count > self.lastMeaningfulTranscript.count + 2
                if hasNewContent {
                    self.lastMeaningfulTranscript = self.currentTranscript
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
        ttsService?.onPlaybackFinished = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
        setupAudioSession()
        connectWithTimeout(to: settings.gatewayURL)
        setupWakeWordListening()
    }

    func toggleSpeaker() {
        isLoudSpeaker.toggle()
        let session = AVAudioSession.sharedInstance()
        let options: AVAudioSession.CategoryOptions = isLoudSpeaker
            ? [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            : [.allowBluetooth, .allowBluetoothA2DP]
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
        try? session.setActive(true)
    }

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                                    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("AudioSession setup error: \(error)")
        }
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
                ttsService?.stopSpeaking()
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
        accumulatedText = ""
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
        // Stop engine trước để AVAudioPlayer không bị conflict
        audioService.stopEngineForPlayback()
        let voiceID = settings.selectedVoiceID.isEmpty ? "nova" : settings.selectedVoiceID
        ttsService?.speak(text: text, voiceID: voiceID, language: settings.sttLanguage)
    }

    // MARK: - AI Interrupt

    private func interruptAI() {
        ttsService?.stopSpeaking()
        chatState = .idle
    }

    // MARK: - Wake Word

    private func handleWakeWord(_ phrase: String) {
        DispatchQueue.main.async {
            // Stop any current activity
            self.ttsService?.stopSpeaking()
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
        deepgramService = STTService(apiKey: newSettings.deepgramAPIKey, language: newSettings.sttLanguage)
        ttsService = TTSService(apiKey: newSettings.ttsAPIKey)
        ttsService?.openAIKey = newSettings.openAIKey
        ttsService?.onPlaybackFinished = { [weak self] in
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
