import AVFoundation
import Foundation
import Combine

/// Chat states for the always-on mic architecture.
enum ChatState: Equatable {
    case connecting       // Initial connection to relay/gateway
    case idle             // Wake word listening
    case listening        // User speaking, sending to relay/STT
    case aiThinking       // Waiting for AI, pre-buffering mic
    case aiSpeaking       // TTS playing, pre-buffering mic with threshold gating
    case error(String)    // Error state
}

/// Singleton AVAudioEngine manager.
/// The engine starts when ChatView appears and stops only when ChatView disappears.
/// Never stops/restarts between turns to avoid AirPods HW format mismatch crashes.
final class AudioEngine: ObservableObject {
    static let shared = AudioEngine()

    // MARK: - Published State

    @Published private(set) var isRunning = false
    @Published var chatState: ChatState = .connecting {
        didSet {
            guard chatState != oldValue else { return }
            print("[AudioEngine] state: \(oldValue) -> \(chatState)")

            // Mic gain management: reduce as soon as AI takes over, restore when user speaks
            // Echo suppression relies on voiceChat AEC + software echo gate
            // Hardware inputGain not supported on most devices — no-op
        }
    }
    @Published var inputLevel: Float = 0.0

    // MARK: - Buffer Consumers

    /// Called in idle state for wake word detection (native format buffer).
    var wakeWordConsumer: ((AVAudioPCMBuffer) -> Void)?

    /// Called in listening state for relay streaming (converted PCM buffer).
    var relayConsumer: ((AVAudioPCMBuffer, Float) -> Void)?

    /// Called in listening state for on-device STT (native format buffer).
    var onDeviceSTTConsumer: ((AVAudioPCMBuffer) -> Void)?

    /// Called in aiThinking/aiSpeaking states for pre-buffering (converted PCM buffer).
    var preBufferConsumer: ((AVAudioPCMBuffer, Float) -> Void)?

    // MARK: - Thresholds

    /// Whether loud speaker (external) is active — set by ChatViewModel
    var isLoudSpeaker: Bool = false

    /// Scale factors for echo gate per speaker mode
    /// AirPods/headphone: no threshold needed (acoustic isolation)
    /// Inner speaker: mild scaling
    /// Loud speaker: aggressive scaling
    /// Echo gate: suppress TTS mic feedback. factor × volume, capped at 0.80.
    private let echoGateFactor: [String: Float] = [
        "airpods":   0.00,  // AirPods — acoustic isolation, no echo
        "headphone": 0.00,  // wired — no echo
        "inner":     0.25,  // inner speaker — mild feedback
        "loud":      0.70,  // loud speaker — heavy feedback
    ]

    /// Barge-in: detect intentional user interruption during TTS.
    /// Independent from echo gate — absolute threshold per mode.
    private let bargeInByMode: [String: Float] = [
        "airpods":   0.30,  // easy — no echo risk
        "headphone": 0.30,  // easy — no echo risk
        "inner":     0.55,  // moderate
        "loud":      0.95,  // very hard — must shout above TTS echo
    ]

    /// Current output mode — set by ChatViewModel
    var outputMode: String = "inner"  // "airpods" | "headphone" | "inner" | "loud"

    /// Echo gate threshold = factor × volume, capped at 0.80
    var echoGateThreshold: Float {
        let volume = AVAudioSession.sharedInstance().outputVolume
        let factor = echoGateFactor[outputMode] ?? 0.25
        return min(factor * volume, 0.80)
    }

    /// Barge-in threshold — absolute per mode, independent of echo gate
    var bargeInThreshold: Float {
        return bargeInByMode[outputMode] ?? 0.55
    }

    // MARK: - Private

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat

    private init() {
        // Target format for relay/STT: PCM 16kHz int16 mono
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    }

    // MARK: - Engine Lifecycle

    /// Start the audio engine. Call when ChatView appears.
    func startEngine() {
        guard !isRunning else {
            print("[AudioEngine] already running")
            return
        }

        // Setup audio session first
        AudioSessionManager.shared.setupForChat(loudSpeaker: false)

        let inputNode = engine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        // Create converter from native format to target format
        converter = AVAudioConverter(from: nativeFormat, to: targetFormat)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nativeFormat) { [weak self] buffer, _ in
            self?.handleAudioBuffer(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            print("[AudioEngine] started, native format: \(nativeFormat)")
        } catch {
            print("[AudioEngine] start error: \(error)")
            isRunning = false
        }
    }

    /// Stop the audio engine. Call when ChatView disappears.
    func restartEngine() {
        stopEngine()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.startEngine()
        }
    }

    func stopEngine() {
        guard isRunning else { return }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        converter = nil

        AudioSessionManager.shared.deactivate()
        print("[AudioEngine] stopped")
    }

    // MARK: - Audio Processing

    private func handleAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert to target format
        guard let converted = convertBuffer(buffer) else { return }

        // Compute RMS level
        let rms = computeRMS(from: converted)

        // Update input level on main thread
        DispatchQueue.main.async {
            self.inputLevel = rms
        }

        // Route buffer based on current state
        switch chatState {
        case .idle:
            // Feed to wake word service (native buffer for SFSpeechRecognizer)
            wakeWordConsumer?(buffer)

        case .listening:
            // Feed to relay (converted PCM) and on-device STT (native buffer)
            relayConsumer?(converted, rms)
            onDeviceSTTConsumer?(buffer)

        case .aiThinking:
            // Pre-buffer (no threshold gating yet)
            preBufferConsumer?(converted, rms)

        case .aiSpeaking:
            // Always pass to preBufferConsumer — barge-in detection happens there
            // Consumer applies its own bargeInThreshold check independently of echo gate
            preBufferConsumer?(converted, rms)

        case .connecting, .error:
            // Don't process audio in these states
            break
        }
    }

    // MARK: - Audio Conversion

    private func convertBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let conv = converter else { return nil }

        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return nil
        }

        var filled = false
        var error: NSError?

        conv.convert(to: outputBuffer, error: &error) { _, status in
            if !filled {
                filled = true
                status.pointee = .haveData
                return buffer
            }
            status.pointee = .noDataNow
            return nil
        }

        return error == nil ? outputBuffer : nil
    }

    // MARK: - RMS Computation

    func computeRMS(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.int16ChannelData, buffer.frameLength > 0 else { return 0 }

        var sum: Float = 0
        let frameCount = Int(buffer.frameLength)

        for i in 0..<frameCount {
            let sample = Float(channelData[0][i]) / 32768.0
            sum += sample * sample
        }

        // Scale RMS for better visual feedback
        return min(sqrt(sum / Float(frameCount)) * 8.0, 1.0)
    }

    /// Compute RMS from native format buffer (for wake word service).
    func computeRMSNative(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return 0 }

        var sum: Float = 0
        let frameCount = Int(buffer.frameLength)

        for i in 0..<frameCount {
            let sample = channelData[0][i]
            sum += sample * sample
        }

        return min(sqrt(sum / Float(frameCount)) * 4.0, 1.0)
    }

    // MARK: - PCM Data Extraction

    /// Extract raw PCM int16 data for relay streaming.
    func pcmData(from buffer: AVAudioPCMBuffer) -> Data {
        guard let channelData = buffer.int16ChannelData else { return Data() }
        return Data(bytes: channelData[0], count: Int(buffer.frameLength) * 2)
    }
}
