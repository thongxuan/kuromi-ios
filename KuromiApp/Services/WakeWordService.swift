import Foundation
import Speech
import AVFoundation
import Combine

class WakeWordService: ObservableObject {
    @Published var isListening: Bool = false
    @Published var recognizedText: String = ""

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    var wakeWord: String = "hey kuromi"
    var onWakeWordDetected: ((String) -> Void)?

    // MARK: - Permission

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    // MARK: - Listening

    func startListening(audioEngine: AVAudioEngine) {
        guard !isListening, speechRecognizer?.isAvailable == true else { return }
        stopListening()

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
                    DispatchQueue.main.async {
                        self.onWakeWordDetected?(text)
                    }
                    self.restartListening(audioEngine: audioEngine)
                }
            }
            if error != nil {
                self.restartListening(audioEngine: audioEngine)
            }
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        DispatchQueue.main.async { self.isListening = true }
    }

    func stopListening() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        DispatchQueue.main.async { self.isListening = false }
    }

    private func restartListening(audioEngine: AVAudioEngine) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startListening(audioEngine: audioEngine)
        }
    }

    // MARK: - Training: Record sample

    private var trainingEngine = AVAudioEngine()
    private var trainingRecognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var trainingTask: SFSpeechRecognitionTask?
    var onTrainingSampleCaptured: ((String) -> Void)?

    func recordTrainingSample() {
        trainingRecognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = trainingRecognitionRequest else { return }
        request.shouldReportPartialResults = false

        var finalText = ""

        trainingTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            if let result = result, result.isFinal {
                finalText = result.bestTranscription.formattedString
                self?.onTrainingSampleCaptured?(finalText)
                self?.stopTrainingRecording()
            }
        }

        let inputNode = trainingEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.trainingRecognitionRequest?.append(buffer)
        }

        do {
            try trainingEngine.start()
        } catch {
            print("Training engine start error: \(error)")
        }
    }

    func stopTrainingRecording() {
        trainingEngine.inputNode.removeTap(onBus: 0)
        trainingEngine.stop()
        trainingRecognitionRequest?.endAudio()
        trainingTask?.cancel()
        trainingRecognitionRequest = nil
        trainingTask = nil
    }
}
