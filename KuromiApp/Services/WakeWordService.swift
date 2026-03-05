import Foundation
import Speech
import AVFoundation

class WakeWordService: ObservableObject {
    @Published var isListening = false

    var wakePhrase: String = "kuromi"
    var onDetected: (() -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var restartWorkItem: DispatchWorkItem?
    private var isActive = false

    func start(language: String) {
        guard !isActive else { return }
        isActive = true
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized, let self = self else { return }
                self.beginListening(language: language)
            }
        }
    }

    func stop() {
        isActive = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        teardown()
        DispatchQueue.main.async { self.isListening = false }
    }

    private func beginListening(language: String) {
        guard isActive else { return }
        teardown()

        let locale = Locale(identifier: language == "vi" ? "vi-VN" : "en-US")
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        guard speechRecognizer?.isAvailable == true else {
            scheduleRestart(language: language, after: 3.0); return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            scheduleRestart(language: language, after: 2.0); return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.isActive else { return }
            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                if text.contains(self.wakePhrase.lowercased()) {
                    print("[wake] detected: \(text)")
                    DispatchQueue.main.async { self.onDetected?() }
                    self.scheduleRestart(language: language, after: 2.0) // cooldown
                    return
                }
                if result.isFinal { self.scheduleRestart(language: language, after: 0.3) }
            }
            if error != nil { self.scheduleRestart(language: language, after: 1.0) }
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
        } catch {
            scheduleRestart(language: language, after: 2.0)
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

    private func scheduleRestart(language: String, after delay: TimeInterval) {
        guard isActive else { return }
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.beginListening(language: language) }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
