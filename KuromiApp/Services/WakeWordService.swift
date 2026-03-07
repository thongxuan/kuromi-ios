import Foundation
import Speech
import AVFoundation

/// Wake word detection service using SFSpeechRecognizer.
/// Uses shared AudioEngine for audio input - does NOT manage its own AVAudioEngine.
class WakeWordService: ObservableObject {
    @Published var isListening = false

    var wakePhrase: String = "kuromi"
    var onDetected: (() -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartWorkItem: DispatchWorkItem?
    private var isActive = false
    private var currentLanguage: String = "en"

    // MARK: - Public API

    func start(language: String) {
        print("[wake] start() called, isActive=\(isActive), phrase='\(wakePhrase)', lang=\(language)")
        guard !isActive else {
            print("[wake] already active, skip")
            return
        }
        isActive = true
        currentLanguage = language

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                print("[wake] auth status: \(status.rawValue)")
                guard let self = self else { return }
                guard status == .authorized else {
                    print("[wake] not authorized, aborting")
                    self.isActive = false
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

    /// Called by AudioEngine tap in idle state.
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    // MARK: - Private

    private func beginListening(language: String) {
        print("[wake] beginListening(), isActive=\(isActive)")
        guard isActive else {
            print("[wake] not active, skip beginListening")
            return
        }
        teardown()

        let localeId = Self.localeId(for: language)
        print("[wake] using locale: \(localeId)")
        let locale = Locale(identifier: localeId)
        speechRecognizer = SFSpeechRecognizer(locale: locale)

        guard let recognizer = speechRecognizer else {
            print("[wake] SFSpeechRecognizer init failed for locale \(localeId)")
            scheduleRestart(language: language, after: 3.0)
            return
        }
        print("[wake] recognizer available: \(recognizer.isAvailable), supportsOnDevice: \(recognizer.supportsOnDeviceRecognition)")
        guard recognizer.isAvailable else {
            print("[wake] recognizer not available, retry in 3s")
            scheduleRestart(language: language, after: 3.0)
            return
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
                    print("[wake] wake phrase detected!")
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

        DispatchQueue.main.async {
            self.isListening = true
            print("[wake] listening for '\(self.wakePhrase)'")
        }
    }

    private func teardown() {
        print("[wake] teardown()")
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    static func localeId(for language: String) -> String {
        let map: [String: String] = [
            "vi": "vi-VN", "en": "en-US", "ja": "ja-JP",
            "zh": "zh-CN", "ko": "ko-KR", "fr": "fr-FR",
            "de": "de-DE", "es": "es-ES"
        ]
        return map[language] ?? "en-US"
    }

    private func scheduleRestart(language: String, after delay: TimeInterval) {
        guard isActive else { return }
        print("[wake] scheduleRestart in \(delay)s")
        restartWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.beginListening(language: language)
        }
        restartWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
