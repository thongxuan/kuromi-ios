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
    private var wakeWordService = WakeWordService()
    private var settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var connectTimer: Timer?
    private var stopTimeoutTimer: Timer?
    private var isStopping: Bool = false      // true between stopChat() and finalizeStop()
    private var ignoreNextTTSEnd: Bool = false
    private var pendingWakeWordResume: Bool = false  // resume wake word after TTS end/timeout

    // MARK: - Init

    init() {
        settings = AppSettings.load()!
        setupRelay()
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
        wakeWordService.stop()
    }

    func reconnect() {
        showReconnectButton = false
        reconnectAttemptCount += 1
        relayService.reconnect()
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
    private func startChat(beep: Bool = false) {
        // Cancel any pending stop state
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
        isStopping = false
        ignoreNextTTSEnd = false
        pendingWakeWordResume = false

        wakeWordService.stop()
        chatState = .userSpeaking
        currentTranscript = ""
        inputLevel = 0.0

        if beep {
            AudioServicesPlaySystemSound(1322) // "Anticipate" — ascending chime
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.relayService.startMic()
            }
        } else {
            relayService.startMic()
        }
    }

    /// End a chat turn — called by: orb tap, stop phrase detection
    private func stopChat() {
        guard case .userSpeaking = chatState else { return }
        isStopping = true
        chatState = .idle
        inputLevel = 0.0

        AudioServicesPlaySystemSound(1114) // descending tone
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.relayService.stopMic()
        }
        // 5s fallback — if TTS never arrives (stop before AI responded), finalize anyway
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.finalizeStop()
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
                    if !text.isEmpty { self.messages.append(Message(role: .user, text: text)) }
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
            }
        }

        relayService.onTTSEnd = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.ignoreNextTTSEnd {
                    self.ignoreNextTTSEnd = false
                    self.chatState = .idle
                    self.inputLevel = 0.0
                    // Resume wake word now that final TTS has ended
                    if self.pendingWakeWordResume {
                        self.pendingWakeWordResume = false
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
                if self.isStopping { self.finalizeStop(fromMicStop: true) }
            }
        }

        relayService.connect(gatewayURL: settings.gatewayURL, language: settings.sttLanguage, voice: "NF", token: settings.gatewayToken)
        setupWakeWord()
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
            .sink { [weak self] _ in self?.relayService.appDidBecomeActive() }
            .store(in: &cancellables)
    }
}
