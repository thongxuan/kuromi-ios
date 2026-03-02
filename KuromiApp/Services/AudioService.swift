import AVFoundation
import Combine

class AudioService: NSObject, ObservableObject {
    static let shared = AudioService()

    private let audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var playerNode = AVAudioPlayerNode()

    @Published var inputLevel: Float = 0.0
    @Published var isRecording = false
    @Published var isPlaying = false

    private var audioBufferCallback: ((AVAudioPCMBuffer) -> Void)?
    private var playbackQueue: [Data] = []
    private var isPlaybackScheduled = false

    override init() {
        super.init()
        setupAudioSession()
        setupEngine()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            print("AudioSession setup error: \(error)")
        }
    }

    private func setupEngine() {
        audioEngine.attach(playerNode)
        let mainMixer = audioEngine.mainMixerNode
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        audioEngine.connect(playerNode, to: mainMixer, format: format)
    }

    // MARK: - Recording

    func startRecording(bufferCallback: @escaping (AVAudioPCMBuffer) -> Void) {
        guard !isRecording else { return }
        audioBufferCallback = bufferCallback

        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            // Calculate level
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameCount { sum += abs(channelData[i]) }
                DispatchQueue.main.async {
                    self.inputLevel = frameCount > 0 ? sum / Float(frameCount) : 0
                }
            }
            bufferCallback(buffer)
        }

        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
            DispatchQueue.main.async { self.isRecording = true }
        } catch {
            print("AudioEngine start error: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async {
            self.isRecording = false
            self.inputLevel = 0
        }
    }

    // MARK: - Playback

    func playAudioData(_ data: Data) {
        playbackQueue.append(data)
        if !isPlaybackScheduled {
            scheduleNextPlayback()
        }
    }

    private func scheduleNextPlayback() {
        guard !playbackQueue.isEmpty else {
            isPlaybackScheduled = false
            DispatchQueue.main.async { self.isPlaying = false }
            return
        }

        isPlaybackScheduled = true
        DispatchQueue.main.async { self.isPlaying = true }

        let data = playbackQueue.removeFirst()
        guard let buffer = pcmBuffer(from: data) else {
            scheduleNextPlayback()
            return
        }

        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }

        playerNode.scheduleBuffer(buffer) { [weak self] in
            DispatchQueue.main.async {
                self?.scheduleNextPlayback()
            }
        }
    }

    private func pcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 24000
        let channels: AVAudioChannelCount = 1
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false) else { return nil }
        let frameCount = UInt32(data.count / 2) // 16-bit PCM
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount

        data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            let int16Ptr = ptr.bindMemory(to: Int16.self)
            if let floatData = buffer.floatChannelData?[0] {
                for i in 0..<Int(frameCount) {
                    floatData[i] = Float(int16Ptr[i]) / 32768.0
                }
            }
        }
        return buffer
    }

    func stopPlayback() {
        playerNode.stop()
        playbackQueue.removeAll()
        isPlaybackScheduled = false
        DispatchQueue.main.async { self.isPlaying = false }
    }

    // MARK: - PCM conversion helper for Deepgram

    static func convertBufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        var int16Samples = [Int16](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            let sample = max(-1.0, min(1.0, channelData[i]))
            int16Samples[i] = Int16(sample * 32767)
        }
        return Data(bytes: &int16Samples, count: frameCount * 2)
    }
}
