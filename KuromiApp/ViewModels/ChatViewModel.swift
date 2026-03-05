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

    private var relayService = AudioRelayService()
    private var wakeWordService = WakeWordService()
    private var settings: AppSettings
    private var cancellables = Set<AnyCancellable>()
    private var connectTimer: Timer?
    private var silenceTimer: Timer?
    private var accumulatedText: String = ""
    private var sessionStopped: Bool = false      // true after stop phrase — ignore new AI events
    private var stopTimeoutTimer: Timer?           // 5s fallback to fully reset

    init() {
        settings = AppSettings.load()!
        setupRelay()
        observeForeground()
    }

    // MARK: - Setup

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
                // Stop phrase check — handled entirely on iOS
                let sp = self.settings.stopPhrase.trimmingCharacters(in: .whitespaces)
                if !sp.isEmpty && fuzzyContains(text, phrase: sp, threshold: 0.7) {
                    print("[chat] stop phrase detected: '\(text)'")
                    // Add to conversation first, then stop
                    if !text.isEmpty {
                        self.messages.append(Message(role: .user, text: text))
                    }
                    self.currentTranscript = ""
                    self.accumulatedText = ""
                    self.stopUserSpeaking()
                    return
                }
                // Ignore transcripts if already stopped (e.g. relay sends final after iOS stop)
                guard case .userSpeaking = self.chatState else { return }
                if isFinal && !text.isEmpty {
                    self.messages.append(Message(role: .user, text: text))
                    self.currentTranscript = ""
                    self.accumulatedText = ""
                    self.chatState = .idle
                } else if !isFinal {
                    self.currentTranscript = text
                }
            }
        }
        relayService.onAIText = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self, !text.isEmpty else { return }
                guard !self.sessionStopped else { return }
                self.messages.append(Message(role: .assistant, text: text))
            }
        }
        relayService.onTTSStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, !self.sessionStopped else { return }
                self.chatState = .aiSpeaking
            }
        }
        relayService.onTTSEnd = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // If stopped, this is the last response — fully reset
                if self.sessionStopped {
                    self.finalizeStop()
                    return
                }
                self.chatState = .idle
                self.inputLevel = 0.0
                if self.isToggleEnabled {
                    self.startUserSpeaking()
                }
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
            }
        }

        relayService.connect(gatewayURL: settings.gatewayURL, language: settings.sttLanguage, voice: "NF", token: settings.gatewayToken)
        setupWakeWord()
    }

    private func observeForeground() {
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.relayService.appDidBecomeActive() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func onAppear() {
        setupAudioSession()
        // Relay already connects in init; show reconnect if still connecting after 5s
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, case .connecting = self.chatState else { return }
                self.showReconnectButton = true
            }
        }
    }

    func onDisappear() {
        stopUserSpeaking()
        wakeWordService.stop()
    }

    private func setupWakeWord() {
        guard !settings.wakePhrase.isEmpty else { return }
        wakeWordService.wakePhrase = settings.wakePhrase
        wakeWordService.onDetected = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self, case .idle = self.chatState, self.isToggleEnabled else { return }
                self.wakeWordService.stop()
                self.startUserSpeaking(playBeep: true)
            }
        }
        wakeWordService.start(language: settings.sttLanguage)
    }

    private func resumeWakeWord() {
        guard !settings.wakePhrase.isEmpty else { return }
        wakeWordService.start(language: settings.sttLanguage)
    }

    func reconnect() {
        showReconnectButton = false
        reconnectAttemptCount += 1
        relayService.reconnect()
    }

    // MARK: - Audio Session

    func toggleSpeaker() {
        isLoudSpeaker.toggle()
        UserDefaults.standard.set(isLoudSpeaker, forKey: "kuromi_loud_speaker")
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try? session.setActive(true)
        try? session.overrideOutputAudioPort(isLoudSpeaker ? .speaker : .none)
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try? session.setActive(true)
        if isLoudSpeaker { try? session.overrideOutputAudioPort(.speaker) }
    }

    // MARK: - Toggle Speaking

    func toggleSpeaking() {
        switch chatState {
        case .idle, .aiSpeaking:
            startUserSpeaking(playBeep: true)
        case .userSpeaking:
            stopUserSpeaking()
        default:
            break
        }
    }

    private func startUserSpeaking(playBeep: Bool = false) {
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
        sessionStopped = false
        wakeWordService.stop()
        chatState = .userSpeaking
        currentTranscript = ""
        accumulatedText = ""
        if playBeep {
            AudioServicesPlaySystemSound(1113) // iOS recording start sound
            // Delay mic start slightly so beep isn't cut off by audio session switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.relayService.startMic()
            }
        } else {
            relayService.startMic()
        }
    }

    private func stopUserSpeaking() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        sessionStopped = true
        chatState = .idle
        AudioServicesPlaySystemSound(1114) // iOS recording stop sound — play before stopMic closes audio session
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.relayService.stopMic()
        }
        // 5s fallback — if no TTS end arrives, reset anyway
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.finalizeStop()
        }
    }

    private func finalizeStop() {
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
        sessionStopped = false
        chatState = .idle
        inputLevel = 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.resumeWakeWord()
        }
    }
}
