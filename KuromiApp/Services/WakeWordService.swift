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
        print("[wake] start() called, isActive=\(isActive), phrase='\(wakePhrase)', lang=\(language)")
        guard !isActive else {
            print("[wake] already active, skip")
            return
        }
        isActive = true
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                print("[wake] auth status: \(status.rawValue)") // 0=notDetermined 1=denied 2=restricted 3=authorized
                guard let self = self else { return }
                guard status == .authorized else {
                    print("[wake] not authorized, aborting")
                    return
                }
                self.beginListening(language: language)
            }
        }
    }

    func stop() {
        print("[wake] stop() called")
        isActive = false
        restartWorkItem?.cancel()
        restartWorkItem = nil
        teardown()
        DispatchQueue.main.async { self.isListening = false }
    }

    private func beginListening(language: String) {
        print("[wake] beginListening(), isActive=\(isActive)")
        guard isActive else { print("[wake] not active, skip beginListening"); return }
        teardown()

        let localeId = language == "vi" ? "vi-VN" : "en-US"
        print("[wake] using locale: \(localeId)")
        let locale = Locale(identifier: localeId)
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        guard let recognizer = speechRecognizer else {
            print("[wake] SFSpeechRecognizer init failed for locale \(localeId)")
            scheduleRestart(language: language, after: 3.0); return
        }
        print("[wake] recognizer available: \(recognizer.isAvailable), supportsOnDevice: \(recognizer.supportsOnDeviceRecognition)")
        guard recognizer.isAvailable else {
            print("[wake] recognizer not available, retry in 3s")
            scheduleRestart(language: language, after: 3.0); return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[wake] audio session active")
        } catch {
            print("[wake] audio session error: \(error), retry in 2s")
            scheduleRestart(language: language, after: 2.0); return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            print("[wake] failed to create recognition request")
            return
        }
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        print("[wake] requiresOnDeviceRecognition=\(request.requiresOnDeviceRecognition)")

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.isActive else { return }
            if let error = error {
                print("[wake] recognition error: \(error.localizedDescription)")
                self.scheduleRestart(language: language, after: 1.0)
                return
            }
            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                print("[wake] heard: '\(text)' (isFinal=\(result.isFinal))")
                if fuzzyContains(text, phrase: self.wakePhrase, threshold: 0.7) {
                    print("[wake] ✅ wake phrase detected!")
                    DispatchQueue.main.async { self.onDetected?() }
                    self.scheduleRestart(language: language, after: 2.0)
                    return
                }
                if result.isFinal {
                    print("[wake] final without match, restarting")
                    self.scheduleRestart(language: language, after: 0.3)
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        print("[wake] installing tap, format: \(format)")
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            print("[wake] 🎤 audio engine started, listening for '\(wakePhrase)'")
            DispatchQueue.main.async { self.isListening = true }
        } catch {
            print("[wake] audio engine error: \(error), retry in 2s")
            scheduleRestart(language: language, after: 2.0)
        }
    }

    private func teardown() {
        print("[wake] teardown()")
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
        print("[wake] scheduleRestart in \(delay)s")
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.beginListening(language: language) }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
