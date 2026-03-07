import Foundation
import Speech
import AVFoundation

/// On-device STT service using SFSpeechRecognizer.
/// Uses shared AudioEngine for audio input - does NOT manage its own AVAudioEngine.
class OnDeviceSTTService {
    var onTranscript: ((String, Bool) -> Void)?
    var onFinalTranscript: ((String) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isActive = false

    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.5
    private var lastTranscript = ""
    private var finalTriggered = false

    // MARK: - Public API

    func start(language: String) {
        guard !isActive else { return }
        isActive = true
        finalTriggered = false

        let localeId = WakeWordService.localeId(for: language)
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[stt] recognizer not available")
            isActive = false
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else {
            isActive = false
            return
        }
        request.shouldReportPartialResults = true
        // requiresOnDeviceRecognition=true can fail with error 1101 if model not downloaded
        request.requiresOnDeviceRecognition = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.isActive else { return }

            if let error = error {
                print("[stt] error: \(error.localizedDescription)")
                let text = self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastTranscript = ""
                self.clearSilenceTimer()
                if !text.isEmpty && !self.finalTriggered {
                    self.finalTriggered = true
                    DispatchQueue.main.async { self.onFinalTranscript?(text) }
                }
                return
            }

            guard let result = result else { return }
            let text = result.bestTranscription.formattedString

            DispatchQueue.main.async {
                self.lastTranscript = text
                self.onTranscript?(text, result.isFinal)
                self.resetSilenceTimer()

                if result.isFinal {
                    self.clearSilenceTimer()
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty && !self.finalTriggered {
                        self.finalTriggered = true
                        self.onFinalTranscript?(trimmed)
                    }
                }
            }
        }

        print("[stt] started, onDevice=\(request.requiresOnDeviceRecognition), locale=\(localeId)")
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        finalTriggered = false
        clearSilenceTimer()

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        lastTranscript = ""
        print("[stt] stopped")
    }

    /// Called by AudioEngine in listening state (on-device mode).
    /// Receives native format buffer for SFSpeechRecognizer.
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        clearSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            let text = self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty && !self.finalTriggered else { return }
            self.lastTranscript = ""
            self.finalTriggered = true
            print("[stt] silence timeout, finalizing: \(text.prefix(60))")
            self.onFinalTranscript?(text)
        }
    }

    private func clearSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
}
