import Foundation
import AVFoundation
import Combine
import UIKit

class ChatViewModel: ObservableObject {

    // MARK: - Published State

    @Published var messages: [Message] = []
    @Published var currentTranscript: String = ""
    @Published var currentAIResponse: String = ""
    @Published var isToggleEnabled: Bool = false
    @Published var showReconnectButton: Bool = false
    @Published var reconnectAttemptCount: Int = 0
    @Published var isLoudSpeaker: Bool = UserDefaults.standard.object(forKey: "kuromi_loud_speaker") == nil
        ? true : UserDefaults.standard.bool(forKey: "kuromi_loud_speaker")
    @Published var isSessionActive: Bool = false

    /// Expose chatState from AudioEngine.
    var chatState: ChatState {
        AudioEngine.shared.chatState
    }

    /// Expose inputLevel from AudioEngine.
    var inputLevel: Float {
        AudioEngine.shared.inputLevel
    }

    // MARK: - Services

    private let audioEngine = AudioEngine.shared
    private var relayService = AudioRelayService()
    private var gatewayService = GatewayService()
    private var wakeWordService = WakeWordService()
    private var onDeviceSTTService = OnDeviceSTTService()
    private var onDeviceTTSService = OnDeviceTTSService()

    // MARK: - Settings

    private var settings: AppSettings
    private var isOnDeviceMode: Bool { settings.useOnDeviceVoice }
    var wakePhrase: String { settings.wakePhrase }

    // MARK: - Private State

    private var accumulatedResponse: String = ""
    private var preBufferText: String = ""  // STT text accumulated during aiThinking/aiSpeaking
    private var cancellables = Set<AnyCancellable>()
    private var connectTimer: Timer?
    private var speakerStateBeforeHeadphones: Bool? = nil
    private var bargeInStartTime: Date? = nil          // sustained barge-in detection
    private let bargeInSustainMs: Double = 300         // must exceed threshold for 300ms

    // MARK: - Init

    init() {
        settings = AppSettings.load()!

        // Setup buffer consumers
        setupAudioEngineConsumers()

        // Setup services
        if isOnDeviceMode {
            setupGatewayDirect()
            setupOnDeviceTTS()
            setupOnDeviceSTT()
        } else {
            setupRelay()
        }
        setupWakeWord()
        setupHeadphoneHandling()
        observeForeground()
        observeAudioEngineState()
    }

    // MARK: - View Lifecycle

    func onAppear() {
        // Start the always-on audio engine
        AudioSessionManager.shared.setupForChat(loudSpeaker: isLoudSpeaker)
        audioEngine.isLoudSpeaker = isLoudSpeaker
        updateOutputMode()
        audioEngine.startEngine()

        // Start connection
        connectTimer?.invalidate()
        connectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, case .connecting = self.chatState else { return }
                self.showReconnectButton = true
            }
        }
    }

    func onDisappear() {
        // Stop wake word and STT
        wakeWordService.stop()
        onDeviceSTTService.stop()
        onDeviceTTSService.stop()

        // Stop the audio engine when leaving ChatView
        audioEngine.stopEngine()
    }

    // MARK: - Public API

    func reconnect() {
        showReconnectButton = false
        reconnectAttemptCount += 1
        if isOnDeviceMode {
            gatewayService.connect(to: settings.gatewayURL, token: settings.gatewayToken)
        } else {
            relayService.reconnect()
        }
    }

    /// Orb tap handler - routes to triggerStart or triggerStop based on state.
    func toggleSpeaking() {
        switch chatState {
        case .idle, .aiSpeaking:
            triggerStart()
        case .listening, .aiThinking:
            triggerStop()
        default:
            break
        }
    }

    func toggleSpeaker() {
        isLoudSpeaker.toggle()
        UserDefaults.standard.set(isLoudSpeaker, forKey: "kuromi_loud_speaker")
        AudioSessionManager.shared.setSpeaker(isLoudSpeaker)
        audioEngine.isLoudSpeaker = isLoudSpeaker
        updateOutputMode()
    }

    private func updateOutputMode() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let hasAirPods = outputs.contains { $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP }
        let hasWired = outputs.contains { $0.portType == .headphones }
        if hasAirPods { audioEngine.outputMode = "airpods" }
        else if hasWired { audioEngine.outputMode = "headphone" }
        else if isLoudSpeaker { audioEngine.outputMode = "loud" }
        else { audioEngine.outputMode = "inner" }
    }

    // MARK: - State Transitions

    /// Start listening - called by orb tap (in idle/aiSpeaking) or wake word.
    /// Plays start beep FIRST, then after 0.5s delay transitions to LISTENING state.
    private func triggerStart() {
        print("[chat] triggerStart()")

        // If AI is speaking, stop TTS first (barge-in from orb tap)
        if case .aiSpeaking = chatState {
            if isOnDeviceMode {
                onDeviceTTSService.stop()
            } else {
                relayService.sendBargeIn()  // abort relay TTS + stop local playback
            }
            relayService.resetBargeIn()
        }

        // Stop wake word (will be resumed when going back to idle)
        wakeWordService.stop()

        // Clear any pre-buffer from previous turn
        preBufferText = ""
        currentTranscript = ""
        accumulatedResponse = ""

        // Play start beep, then after 0.5s delay transition to listening
        SoundPlayer.playStartBeep { [weak self] in
            guard let self = self else { return }
            self.isSessionActive = true
            self.audioEngine.chatState = .listening

            if self.isOnDeviceMode {
                self.onDeviceSTTService.start(language: self.settings.sttLanguage)
            }
            // Relay mode: AudioEngine will route buffers to relayService automatically
        }
    }

    /// Stop listening - called by orb tap (in listening/aiThinking) or stop phrase.
    /// Plays stop beep FIRST, then after 0.5s delay transitions to IDLE state.
    private func triggerStop() {
        print("[chat] triggerStop()")

        // Stop STT immediately
        onDeviceSTTService.stop()

        // Tell relay to stop processing immediately
        if !isOnDeviceMode {
            relayService.sendStopSignal()
        }

        // Clear state
        preBufferText = ""
        currentTranscript = ""

        // Play stop beep, then after 0.5s delay transition to idle
        SoundPlayer.playStopBeep { [weak self] in
            guard let self = self else { return }
            self.isSessionActive = false
            self.audioEngine.chatState = .idle
            self.resumeWakeWord()
        }
    }

    // MARK: - Audio Engine Consumers

    private func setupAudioEngineConsumers() {
        // Wake word consumer (idle state) - receives native format buffer
        audioEngine.wakeWordConsumer = { [weak self] buffer in
            self?.wakeWordService.appendBuffer(buffer)
        }

        // Relay consumer (listening state) - receives converted PCM buffer
        audioEngine.relayConsumer = { [weak self] buffer, rms in
            guard let self = self, !self.isOnDeviceMode else { return }
            // Relay mode: send PCM to relay
            self.relayService.appendBuffer(buffer, rms: rms)
        }

        // On-device STT consumer (listening state) - receives native format buffer
        audioEngine.onDeviceSTTConsumer = { [weak self] buffer in
            guard let self = self, self.isOnDeviceMode else { return }
            // On-device mode: feed to SFSpeechRecognizer
            self.onDeviceSTTService.appendBuffer(buffer)
        }

        // Pre-buffer consumer (aiThinking/aiSpeaking) - for barge-in detection
        audioEngine.preBufferConsumer = { [weak self] buffer, rms in
            guard let self = self else { return }

            // Sustained barge-in detection (both modes)
            // User must speak above threshold for 300ms to trigger — filters out TTS echo spikes
            if case .aiSpeaking = self.audioEngine.chatState {
                if rms > self.audioEngine.bargeInThreshold {
                    if let start = self.bargeInStartTime {
                        if Date().timeIntervalSince(start) * 1000 >= self.bargeInSustainMs {
                            self.bargeInStartTime = nil
                            self.handleBargeIn()
                        }
                    } else {
                        self.bargeInStartTime = Date()
                    }
                } else {
                    self.bargeInStartTime = nil  // reset if drops below threshold
                }
            } else {
                self.bargeInStartTime = nil
            }

            // In relay mode, continue sending audio for pre-buffering on server
            if !self.isOnDeviceMode {
                self.relayService.appendBuffer(buffer, rms: rms)
            }
        }
    }

    private func handleBargeIn() {
        print("[chat] barge-in detected")

        // Stop TTS
        if isOnDeviceMode {
            onDeviceTTSService.stop()
        } else if !isOnDeviceMode {
            relayService.sendBargeIn()  // abort relay TTS immediately on orb tap
        }
        // Relay handles its own barge-in via protocol

        // Flush pre-buffer if any
        if !preBufferText.isEmpty {
            print("[chat] flushing pre-buffer: \(preBufferText.prefix(50))")
            preBufferText = ""
        }

        // Transition to listening (user wants to speak)
        audioEngine.chatState = .listening
        if isOnDeviceMode {
            onDeviceSTTService.start(language: settings.sttLanguage)
        }
    }

    // MARK: - Wake Word

    private func setupWakeWord() {
        guard !settings.wakePhrase.isEmpty else { return }
        wakeWordService.wakePhrase = settings.wakePhrase
        wakeWordService.onDetected = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self,
                      case .idle = self.chatState,
                      self.isToggleEnabled else { return }
                self.triggerStart()
            }
        }
        wakeWordService.start(language: settings.sttLanguage)
    }

    private func resumeWakeWord() {
        guard !settings.wakePhrase.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.wakeWordService.start(language: self?.settings.sttLanguage ?? "en")
        }
    }

    // MARK: - Relay Callbacks

    private func setupRelay() {
        relayService.onReady = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.audioEngine.chatState = .idle
                self.isToggleEnabled = true
                self.showReconnectButton = false
                self.reconnectAttemptCount = 0
            }
        }

        relayService.onDisconnected = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.audioEngine.chatState = .connecting
                self.isToggleEnabled = false
            }
        }

        relayService.onTranscript = { [weak self] text, isFinal in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Check stop phrase
                let sp = self.settings.stopPhrase.trimmingCharacters(in: .whitespaces)
                if !sp.isEmpty && fuzzyContains(text, phrase: sp, threshold: 0.7) {
                    print("[chat] stop phrase: '\(text)'")
                    if isFinal && !text.isEmpty {
                        self.messages.append(Message(role: .user, text: text))
                    }
                    self.currentTranscript = ""
                    self.triggerStop()
                    return
                }

                guard case .listening = self.chatState else { return }

                if isFinal && !text.isEmpty {
                    self.messages.append(Message(role: .user, text: text))
                    self.currentTranscript = ""
                    // Transition to aiThinking - waiting for AI response
                    self.audioEngine.chatState = .aiThinking
                } else if !isFinal {
                    self.currentTranscript = text
                }
            }
        }

        relayService.onAIText = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self, !text.isEmpty else { return }
                self.messages.append(Message(role: .assistant, text: text))
            }
        }

        relayService.onTTSStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.audioEngine.chatState = .aiSpeaking
                AudioSessionManager.shared.setSpeaker(self.isLoudSpeaker)
            }
        }

        relayService.onTTSEnd = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }

                // Flush any pre-buffer text
                if !self.preBufferText.isEmpty {
                    print("[chat] TTS end, flushing pre-buffer")
                    self.preBufferText = ""
                }

                // Auto-continue: silently go back to listening for next turn (NO sound)
                if self.isToggleEnabled {
                    self.audioEngine.chatState = .listening
                    // No sound on auto-resume after TTS
                } else {
                    self.audioEngine.chatState = .idle
                    self.resumeWakeWord()
                }
            }
        }

        relayService.onMicStop = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Relay detected silence - transition to aiThinking (NO sound)
                // Sound only plays on explicit user stop via triggerStop()
                if case .listening = self.chatState {
                    self.audioEngine.chatState = .aiThinking
                }
            }
        }

        relayService.useSpeaker = settings.useSpeaker
        relayService.connect(
            gatewayURL: settings.gatewayURL,
            language: settings.sttLanguage,
            voice: "NF",
            token: settings.gatewayToken,
            textMode: false
        )
    }

    // MARK: - Gateway Direct (On-Device Mode)

    private func setupGatewayDirect() {
        gatewayService.onDelta = { [weak self] delta in
            guard let self = self else { return }
            self.accumulatedResponse += delta
            DispatchQueue.main.async {
                self.currentAIResponse = self.accumulatedResponse
            }
        }

        gatewayService.onResponseComplete = { [weak self] in
            guard let self = self else { return }
            let response = self.accumulatedResponse.trimmingCharacters(in: .whitespacesAndNewlines)

            DispatchQueue.main.async {
                self.currentAIResponse = ""

                guard !response.isEmpty else {
                    self.audioEngine.chatState = .idle
                    self.resumeWakeWord()
                    return
                }

                self.messages.append(Message(role: .assistant, text: response))
                self.audioEngine.chatState = .aiSpeaking
                self.onDeviceTTSService.useLoudSpeaker = self.isLoudSpeaker
                self.onDeviceTTSService.speak(
                    text: response,
                    voiceId: self.settings.onDeviceVoiceId,
                    language: self.settings.sttLanguage
                )
            }
        }

        gatewayService.connect(to: settings.gatewayURL, token: settings.gatewayToken)

        gatewayService.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .connected:
                    self.audioEngine.chatState = .idle
                    self.isToggleEnabled = true
                    self.showReconnectButton = false
                    self.reconnectAttemptCount = 0
                case .connecting:
                    self.audioEngine.chatState = .connecting
                case .disconnected, .error:
                    self.audioEngine.chatState = .connecting
                    self.isToggleEnabled = false
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - On-Device TTS

    private func setupOnDeviceTTS() {
        onDeviceTTSService.onStart = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.audioEngine.chatState = .aiSpeaking
            }
        }

        onDeviceTTSService.onFinish = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.accumulatedResponse = ""

                // Auto-continue to listening silently (NO sound on auto-resume)
                if self.isToggleEnabled {
                    self.audioEngine.chatState = .listening
                    // Start STT immediately without sound
                    self.onDeviceSTTService.start(language: self.settings.sttLanguage)
                } else {
                    self.audioEngine.chatState = .idle
                    self.resumeWakeWord()
                }
            }
        }
    }

    // MARK: - On-Device STT

    private func setupOnDeviceSTT() {
        onDeviceSTTService.onTranscript = { [weak self] text, isFinal in
            guard let self = self else { return }

            // Check stop phrase
            let sp = self.settings.stopPhrase.trimmingCharacters(in: .whitespaces)
            if !sp.isEmpty && fuzzyContains(text, phrase: sp, threshold: 0.7) {
                print("[chat] stop phrase (on-device): '\(text)'")
                if isFinal && !text.isEmpty {
                    DispatchQueue.main.async {
                        self.messages.append(Message(role: .user, text: text))
                    }
                }
                self.onDeviceSTTService.stop()
                DispatchQueue.main.async {
                    self.currentTranscript = ""
                    self.triggerStop()
                }
                return
            }

            guard case .listening = self.audioEngine.chatState else { return }

            DispatchQueue.main.async {
                if !isFinal {
                    self.currentTranscript = text
                }
            }
        }

        onDeviceSTTService.onFinalTranscript = { [weak self] text in
            guard let self = self, case .listening = self.audioEngine.chatState else { return }

            self.onDeviceSTTService.stop()

            DispatchQueue.main.async {
                self.currentTranscript = ""
                // No sound here - silence/final transcript is not user-initiated stop
                // Sound only plays on explicit stop via triggerStop()

                if !text.isEmpty {
                    self.messages.append(Message(role: .user, text: text))
                }

                // Transition to aiThinking
                self.audioEngine.chatState = .aiThinking

                // Send to gateway
                self.accumulatedResponse = ""
                self.gatewayService.sendMessage(text)
            }
        }
    }

    // MARK: - Audio Engine State Observation

    private func observeAudioEngineState() {
        // Observe chatState changes from AudioEngine
        audioEngine.$chatState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // Force UI update when chatState changes
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        audioEngine.$inputLevel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Headphone Handling

    private func setupHeadphoneHandling() {
        AudioSessionManager.shared.onHeadphonesConnected = { [weak self] in
            guard let self = self, self.isLoudSpeaker else { return }
            self.speakerStateBeforeHeadphones = true
            self.isLoudSpeaker = false
            self.audioEngine.isLoudSpeaker = false
            UserDefaults.standard.set(false, forKey: "kuromi_loud_speaker")
            AudioSessionManager.shared.setSpeaker(false)
            self.updateOutputMode()
        }

        AudioSessionManager.shared.onHeadphonesDisconnected = { [weak self] in
            guard let self = self, let previous = self.speakerStateBeforeHeadphones else { return }
            self.isLoudSpeaker = previous
            self.audioEngine.isLoudSpeaker = previous
            UserDefaults.standard.set(previous, forKey: "kuromi_loud_speaker")
            AudioSessionManager.shared.setSpeaker(previous)
            self.speakerStateBeforeHeadphones = nil
            self.updateOutputMode()
        }
    }

    // MARK: - Foreground Observer

    private func observeForeground() {
        // willEnterForeground: only fires on background→foreground, NOT on first launch
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("[lifecycle] willEnterForeground — restarting audio engine + reconnect")

                AudioSessionManager.shared.setupForChat(loudSpeaker: self.isLoudSpeaker)
                self.audioEngine.restartEngine()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if self.isOnDeviceMode {
                        self.gatewayService.connect(to: self.settings.gatewayURL, token: self.settings.gatewayToken)
                    } else {
                        self.relayService.appDidBecomeActive()
                    }
                }
            }
            .store(in: &cancellables)

        // didEnterBackground: stop audio engine to free resources
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("[lifecycle] didEnterBackground — stopping audio engine")
                self.audioEngine.stopEngine()
            }
            .store(in: &cancellables)
    }
}
