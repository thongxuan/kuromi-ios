import Foundation
import Speech
import AVFoundation

class OnDeviceSTTService {
    var onTranscript: ((String, Bool) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onFinalTranscript: ((String) -> Void)?

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isActive = false

    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 1.5
    private var lastTranscript = ""

    func start(language: String) {
        guard !isActive else { return }
        isActive = true

        let localeId = WakeWordService.localeId(for: language)
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeId))

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("[stt] recognizer not available")
            isActive = false
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default,
                                    options: [.allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("[stt] audio session error: \(error)")
            isActive = false
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { isActive = false; return }
        request.shouldReportPartialResults = true
        // requiresOnDeviceRecognition=true can fail with error 1101 if model not downloaded
        // Always use false — server-based STT as fallback is more reliable
        request.requiresOnDeviceRecognition = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self, self.isActive else { return }

            if let error = error {
                print("[stt] error: \(error.localizedDescription)")
                let text = self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lastTranscript = ""
                self.clearSilenceTimer()
                if !text.isEmpty {
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
                    if !trimmed.isEmpty {
                        self.onFinalTranscript?(trimmed)
                    }
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            guard let self = self else { return }
            if let converted = self.convertBuffer(buffer, to: targetFormat) {
                let level = self.computeRMS(from: converted)
                DispatchQueue.main.async { self.onAudioLevel?(level) }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            print("[stt] started, onDevice=\(request.requiresOnDeviceRecognition), locale=\(localeId)")
        } catch {
            print("[stt] engine error: \(error)")
            isActive = false
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        clearSilenceTimer()

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }

        lastTranscript = ""
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        clearSilenceTimer()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            guard let self = self, self.isActive else { return }
            let text = self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            self.lastTranscript = ""
            print("[stt] silence timeout, finalizing: \(text.prefix(60))")
            self.onFinalTranscript?(text)
        }
    }

    private func clearSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - Audio Helpers

    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frames = AVAudioFrameCount(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        var filled = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if !filled { filled = true; status.pointee = .haveData; return buffer }
            status.pointee = .noDataNow; return nil
        }
        return err == nil ? out : nil
    }

    private func computeRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let ch = buffer.int16ChannelData, buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let s = Float(ch[0][i]) / 32768.0
            sum += s * s
        }
        return min(sqrt(sum / Float(buffer.frameLength)) * 8.0, 1.0)
    }
}
