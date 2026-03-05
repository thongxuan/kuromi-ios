import Foundation
import Speech
import AVFoundation

class WakeWordService: ObservableObject {
    @Published var isListening = false
    @Published var recognizedText = ""

    var wakeWord: String = "hey kuromi"
    var onWakeWordDetected: ((String) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var restartWorkItem: DispatchWorkItem?

    // MARK: - Start / Stop

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized, let self = self else { return }
                self.beginListening()
            }
        }
    }

    func stop() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        teardown()
        DispatchQueue.main.async { self.isListening = false }
    }

    // MARK: - Internal

    private func beginListening() {
        teardown()

        // Use language from wakeWord detection — default vi-VN, fallback en-US
        let locale = Locale(identifier: wakeWord.hasPrefix("hey") ? "en-US" : "vi-VN")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard speechRecognizer?.isAvailable == true else {
            scheduleRestart(after: 2.0)
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[wakeword] audio session error: \(error)")
            scheduleRestart(after: 2.0)
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.recognizedText = text }
                if LevenshteinHelper.containsWakeWord(text, wakeWord: self.wakeWord) {
                    DispatchQueue.main.async { self.onWakeWordDetected?(text) }
                    self.scheduleRestart(after: 1.5) // cooldown
                    return
                }
                // SFSpeechRecognizer stops after ~1min silence; restart proactively
                if result.isFinal {
                    self.scheduleRestart(after: 0.3)
                }
            }
            if error != nil {
                self.scheduleRestart(after: 1.0)
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            DispatchQueue.main.async { self.isListening = true }
            print("[wakeword] listening for '\(wakeWord)'")
        } catch {
            print("[wakeword] engine error: \(error)")
            scheduleRestart(after: 2.0)
        }
    }

    private func teardown() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func scheduleRestart(after delay: TimeInterval) {
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.beginListening() }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
