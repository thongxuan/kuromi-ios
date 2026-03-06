import Foundation
import AVFoundation
import Combine
import UIKit
import AudioToolbox

enum ChatState: Equatable {
    case connecting
    case idle
    case userSpeaking
    case aiSpeaking
    case error(String)
}

class ChatViewModel: ObservableObject {

    // MARK: - Published

    @Published var chatState: ChatState = .connecting
    @Published var messages: [Message] = []
    @Published var currentTranscript: String = ""
    @Published var inputLevel: Float = 0.0
    @Published var isToggleEnabled: Bool = false
    @Published var currentAIResponse: String = ""
    @Published var showReconnectButton: Bool = false
    @Published var reconnectAttemptCount: Int = 0
    @Published var isLoudSpeaker: Bool = UserDefaults.standard.object(forKey: "kuromi_loud_speaker") == nil
        ? true : UserDefaults.standard.bool(forKey: "kuromi_loud_speaker")

    // MARK: - Private

    private var relayService = AudioRelayService()
    private var gatewayService = GatewayService()
    private var wakeWordService = WakeWordService()
    private var onDeviceSTTService = OnDeviceSTTService()
    private var onDeviceTTSService = OnDeviceTTSService()
    private var settings: AppSettings
    private var isOnDeviceMode: Bool { settings.useOnDeviceVoice }
    var wakePhrase: String { settings.wakePhrase }
    private var accumulatedResponse: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var connectTimer: Timer?
    private var stopTimeoutTimer: Timer?
    private var isStopping: Bool = false      // true between stopChat() and finalizeStop()
    private var ignoreNextTTSEnd: Bool = false
    private var pendingWakeWordResume: Bool = false  // resume wake word after TTS end/timeout

    // MARK: - Init

    init() {
        settings = AppSettings.load()!
        if isOnDeviceMode {
            setupGatewayDirect()
            setupOnDeviceTTS()
            setupOnDeviceSTT()
        } else {
            setupRelay()
        }
        setupWakeWord()
        observeForeground()
    }

    // MARK: - Public API (called by View)

    func onAppear() {
        setupAudioSession()
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, case .connecting = self.chatState else { return }
                self.showReconnectButton = true
            }
        }
    }

    func onDisappear() {
        stopChat()
        onDeviceSTTService.stop()
        onDeviceTTSService.stop()
        wakeWordService.stop()
    }

    func reconnect() {
        showReconnectButton = false
        reconnectAttemptCount += 1
        if isOnDeviceMode {
            gatewayService.connect(to: settings.gatewayURL, token: settings.gatewayToken)
        } else {
            relayService.reconnect()
        }
    }

    /// Orb tap — toggle between start and stop
    func toggleSpeaking() {
        switch chatState {
        case .idle, .aiSpeaking: startChat(beep: true)
        case .userSpeaking:      stopChat()
        default: break
        }
    }

    func toggleSpeaker() {
        isLoudSpeaker.toggle()
        UserDefaults.standard.set(isLoudSpeaker, forKey: "kuromi_loud_speaker")
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try? session.setActive(true)
        try? session.overrideOutputAudioPort(isLoudSpeaker ? .speaker : .none)
    }

    // MARK: - Core Chat Actions (shared by manual + wake/stop word)

    /// Begin a chat turn — called by: orb tap, wake word detection
    private func startChat(beep: Bool = true) {
        // Cancel any pending stop state
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
        isStopping = false
        ignoreNextTTSEnd = false
        pendingWakeWordResume = false
        accumulatedResponse = ""

        // Stop TTS if playing (barge-in)
        if isOnDeviceMode && onDeviceTTSService.isSpeaking {
            onDeviceTTSService.stop()
        }

        wakeWordService.stop()
        chatState = .userSpeaking
        currentTranscript = ""
        inputLevel = 0.0

        if beep {
            // Deactivate session so system sound plays cleanly, then start mic in callback
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            AudioServicesPlaySystemSoundWithCompletion(1111) { [weak self] in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.setupAudioSession()
                    if self.isOnDeviceMode {
                        self.onDeviceSTTService.start(language: self.settings.sttLanguage)
                    } else {
                        self.relayService.startMic()
                    }
                }
            }
        } else {
            setupAudioSession()
            if isOnDeviceMode {
                onDeviceSTTService.start(language: settings.sttLanguage)
            } else {
                relayService.startMic()
            }
        }
    }

    /// End a chat turn — called by: orb tap, stop phrase detection
    private func stopChat() {
        guard case .userSpeaking = chatState else { return }
        isStopping = true
        chatState = .idle
        inputLevel = 0.0

        // Play stop sound — use AudioServicesPlaySystemSound (no session switch needed)
        AudioServicesPlaySystemSound(1110) // end_record.caf

        if isOnDeviceMode {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self else { return }
                self.onDeviceSTTService.stop()
            }
            // 5s fallback — if TTS never arrives (stop before AI responded), finalize anyway
            stopTimeoutTimer?.invalidate()
            stopTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self, self.isStopping || self.pendingWakeWordResume else { return }
                self.pendingWakeWordResume = false
                self.finalizeStop()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.relayService.stopMic()
            }
            // 5s fallback — if TTS never arrives (stop before AI responded), finalize anyway
            stopTimeoutTimer?.invalidate()
            stopTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self, self.isStopping || self.pendingWakeWordResume else { return }
                self.pendingWakeWordResume = false
                self.finalizeStop()
            }
        }
    }

    /// Called when stop sequence is fully done — re-enable wake word
    private func finalizeStop(fromTTSEnd: Bool = false, fromMicStop: Bool = false) {
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
        isStopping = false
        chatState = .idle
        inputLevel = 0.0

        if fromMicStop {
            // TTS might still be coming — mark pending, resume after TTS end
            ignoreNextTTSEnd = true
            pendingWakeWordResume = true
        } else {
            // fromTTSEnd or timeout — safe to resume now
            pendingWakeWordResume = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.resumeWakeWord()
            }
        }
    }

    // MARK: - Wake Word

    private func setupWakeWord() {
        guard !settings.wakePhrase.isEmpty else { return }
        wakeWordService.wakePhrase = settings.wakePhrase
        wakeWordService.onDetected = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, case .idle = self.chatState, self.isToggleEnabled else { return }
                self.startChat(beep: true)
            }
        }
        wakeWordService.start(language: settings.sttLanguage)
    }

    private func resumeWakeWord() {
        guard !settings.wakePhrase.isEmpty else { return }
        wakeWordService.start(language: settings.sttLanguage)
    }

    // MARK: - Relay Callbacks

    private func setupRelay() {
        relayService.onReady = { [weak self] in
            DispatchQueue.main.async {
                self?.chatState = .idle
                self?.isToggleEnabled = true
                self?.showReconnectButton = false
                self?.reconnectAttemptCount = 0
            }
        }

        relayService.onDisconnected = { [weak self] in
            DispatchQueue.main.async {
                self?.chatState = .connecting
                self?.isToggleEnabled = false
            }
        }

        relayService.onTranscript = { [weak self] text, isFinal in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Stop phrase → same as manual stop
                let sp = self.settings.stopPhrase.trimmingCharacters(in: .whitespaces)
                if !sp.isEmpty && fuzzyContains(text, phrase: sp, threshold: 0.7) {
                    print("[chat] stop phrase: '\(text)'")
                    // Only add to chat once (isFinal), avoid duplicates from partial+final
                    if isFinal && !text.isEmpty && !self.isStopping {
                        self.messages.append(Message(role: .user, text: text))
                    }
                    self.currentTranscript = ""
                    self.inputLevel = 0.0
                    self.stopChat()
                    return
                }
                guard case .userSpeaking = self.chatState else { return }
                if isFinal && !text.isEmpty {
                    self.messages.append(Message(role: .user, text: text))
                    self.currentTranscript = ""
                    self.chatState = .idle
                } else if !isFinal {
                    self.currentTranscript = text
                }
            }
        }

        relayService.onAIText = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self, !text.isEmpty, !self.isStopping else { return }
                self.messages.append(Message(role: .assistant, text: text))
            }
        }

        relayService.onTTSStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.chatState = .aiSpeaking
                self.setupAudioSession()
            }
        }

        relayService.onTTSEnd = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.ignoreNextTTSEnd {
                    self.ignoreNextTTSEnd = false
                    self.chatState = .idle
                    self.inputLevel = 0.0
                    if self.pendingWakeWordResume {
                        self.pendingWakeWordResume = false
                        self.stopTimeoutTimer?.invalidate()   // cancel 5s timer — this path wins
                        self.stopTimeoutTimer = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                            self?.resumeWakeWord()
                        }
                    }
                    return
                }
                if self.isStopping {
                    // TTS was last response after stop — finalize cleanly
                    self.finalizeStop(fromTTSEnd: true)
                    return
                }
                self.chatState = .idle
                self.inputLevel = 0.0
                if self.isToggleEnabled { self.startChat() }
            }
        }

        relayService.onAudioLevel = { [weak self] level in
            self?.inputLevel = level
        }

        relayService.onMicStop = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.chatState = .idle
                self.inputLevel = 0.0
                if self.isStopping {
                    self.finalizeStop(fromMicStop: true)
                } else {
                    print("[sound] playing 1114 — STT done (relay mic_stop)")
                    let s = AVAudioSession.sharedInstance()
                    try? s.setActive(false, options: .notifyOthersOnDeactivation)
                    AudioServicesPlaySystemSound(1110)
                }
            }
        }

        relayService.useSpeaker = settings.useSpeaker
        relayService.connect(gatewayURL: settings.gatewayURL, language: settings.sttLanguage, voice: "NF", token: settings.gatewayToken, textMode: false)
    }

    // MARK: - Gateway Direct (On-Device Mode)

    private func setupGatewayDirect() {
        gatewayService.onDelta = { [weak self] delta in
            guard let self = self else { return }
            self.accumulatedResponse += delta
        }

        gatewayService.onResponseComplete = { [weak self] in
            guard let self = self else { return }
            let response = self.accumulatedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !response.isEmpty else {
                self.chatState = .idle
                self.resumeWakeWord()
                return
            }

            self.messages.append(Message(role: .assistant, text: response))
            self.chatState = .aiSpeaking
            self.onDeviceTTSService.useLoudSpeaker = self.isLoudSpeaker
            self.onDeviceTTSService.speak(
                text: response,
                voiceId: self.settings.onDeviceVoiceId,
                language: self.settings.sttLanguage
            )
        }

        // Connect to gateway
        gatewayService.connect(to: settings.gatewayURL, token: settings.gatewayToken)

        // Observe gateway state
        gatewayService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .connected:
                    self.chatState = .idle
                    self.isToggleEnabled = true
                    self.showReconnectButton = false
                    self.reconnectAttemptCount = 0
                case .connecting:
                    self.chatState = .connecting
                case .disconnected, .error:
                    self.chatState = .connecting
                    self.isToggleEnabled = false
                }
            }
            .store(in: &cancellables)
    }

    private func setupOnDeviceTTS() {
        onDeviceTTSService.onStart = { [weak self] in
            self?.chatState = .aiSpeaking
        }

        onDeviceTTSService.onFinish = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.accumulatedResponse = ""
                if self.isStopping {
                    self.finalizeStop(fromTTSEnd: true)
                } else {
                    self.chatState = .idle
                    self.inputLevel = 0.0
                    if self.isToggleEnabled { self.startChat() }
                }
            }
        }
    }

    // MARK: - On-Device STT

    private func setupOnDeviceSTT() {
        onDeviceSTTService.onTranscript = { [weak self] (text: String, isFinal: Bool) in
            guard let self = self else { return }
            // Stop phrase check
            let sp = self.settings.stopPhrase.trimmingCharacters(in: .whitespaces)
            if !sp.isEmpty && fuzzyContains(text, phrase: sp, threshold: 0.7) {
                print("[chat] stop phrase (on-device): '\(text)'")
                // Only add to chat once (isFinal), avoid duplicates from partial+final
                if isFinal && !text.isEmpty && !self.isStopping {
                    self.messages.append(Message(role: .user, text: text))
                }
                self.onDeviceSTTService.stop()
                self.currentTranscript = ""
                self.inputLevel = 0.0
                self.stopChat()
                return
            }
            guard case .userSpeaking = self.chatState else { return }
            if !isFinal {
                self.currentTranscript = text
            }
        }

        onDeviceSTTService.onAudioLevel = { [weak self] level in
            self?.inputLevel = level
        }

        onDeviceSTTService.onFinalTranscript = { [weak self] (text: String) in
            guard let self = self, case .userSpeaking = self.chatState else { return }
            guard !self.isStopping else { return }  // Don't send to gateway if stopping
            self.onDeviceSTTService.stop()
            self.chatState = .idle
            self.inputLevel = 0.0
            self.currentTranscript = ""
            print("[sound] playing 1114 — STT done (on-device final)")
            let s = AVAudioSession.sharedInstance()
            try? s.setActive(false, options: .notifyOthersOnDeactivation)
            AudioServicesPlaySystemSound(1110)
            if !text.isEmpty {
                self.messages.append(Message(role: .user, text: text))
            }
            // Send to gateway directly in on-device mode
            self.accumulatedResponse = ""
            self.gatewayService.sendMessage(text)
        }
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try? session.setActive(true)
        if isLoudSpeaker { try? session.overrideOutputAudioPort(.speaker) }
    }

    private func observeForeground() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isOnDeviceMode {
                    // Gateway will auto-reconnect if needed
                    if case .disconnected = self.gatewayService.state {
                        self.gatewayService.connect(to: self.settings.gatewayURL, token: self.settings.gatewayToken)
                    }
                } else {
                    self.relayService.appDidBecomeActive()
                }
            }
            .store(in: &cancellables)
    }
}
