import AVFoundation
import Combine

class AudioService: NSObject, ObservableObject {
    static let shared = AudioService()

    let engine = AVAudioEngine()
    private var audioEngine: AVAudioEngine { engine }
    private var inputNode: AVAudioInputNode { engine.inputNode }
    private var playerNode = AVAudioPlayerNode()

    @Published var inputLevel: Float = 0.0
    @Published var isRecording = false
    @Published var isPlaying = false

    private var audioBufferCallback: ((AVAudioPCMBuffer) -> Void)?
    private var playbackQueue: [Data] = []
    private var isPlaybackScheduled = false

    @Published var isUsingBluetooth: Bool = false

    override init() {
        super.init()
        setupAudioSession()
        setupEngine()
        observeRouteChanges()
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("AudioSession setup error: \(error)")
        }
        updateBluetoothState()
    }

    private func observeRouteChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let changeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            switch changeReason {
            case .newDeviceAvailable:
                self.switchToBluetooth()
            case .oldDeviceUnavailable:
                self.switchToSpeaker()
            default:
                break
            }
            self.updateBluetoothState()

            // Restart recording sau khi switch (delay để tránh conflict)
            if self.isRecording {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.restartRecording()
                }
            }
        }
    }

    private func restartRecording() {
        guard let callback = audioBufferCallback else { return }
        // Stop current tap + engine
        if engine.isRunning {
            inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        // Short delay để system cập nhật format mới
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            // Reinstall tap với format mới
            let inputFormat = self.inputNode.outputFormat(forBus: 0)
            self.inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                if let channelData = buffer.floatChannelData?[0] {
                    let frameCount = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<frameCount { sum += abs(channelData[i]) }
                    DispatchQueue.main.async {
                        self.inputLevel = frameCount > 0 ? sum / Float(frameCount) : 0
                    }
                }
                callback(buffer)
            }
            do {
                try self.engine.start()
                print("Audio engine restarted after route change")
            } catch {
                print("Engine restart error: \(error)")
            }
        }
    }

    private func switchToBluetooth() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try? session.setActive(true)
        // Set Bluetooth HFP as preferred input (mic)
        if let btInput = session.availableInputs?.first(where: {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
        }) {
            try? session.setPreferredInput(btInput)
            print("Audio input: \(btInput.portName)")
        }
    }

    private func switchToSpeaker() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try? session.setActive(true)
        try? session.setPreferredInput(nil)
        print("Audio route: switched to Speaker")
    }

    private func updateBluetoothState() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let usingBT = outputs.contains { $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP || $0.portType == .bluetoothLE }
        DispatchQueue.main.async { self.isUsingBluetooth = usingBT }
    }

    private func setupEngine() {
        audioEngine.attach(playerNode)
        let mainMixer = audioEngine.mainMixerNode
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
        audioEngine.connect(playerNode, to: mainMixer, format: format)
    }

    // MARK: - Mic monitoring (không gửi audio, chỉ đo level)

    func startMonitoring() {
        guard !isRecording else { return }
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<frameCount { sum += abs(channelData[i]) }
                DispatchQueue.main.async {
                    self.inputLevel = frameCount > 0 ? sum / Float(frameCount) : 0
                }
            }
        }
        if !engine.isRunning { try? engine.start() }
    }

    func stopMonitoring() {
        guard !isRecording else { return }
        inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async { self.inputLevel = 0 }
    }

    // MARK: - Recording
    // Engine luôn chạy, chỉ add/remove tap để bật tắt recording
    // Không stop engine khi TTS play — dùng .playAndRecord suốt

    private func ensureEngineRunning() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("AudioEngine start error: \(error)")
        }
    }

    func startRecording(bufferCallback: @escaping (AVAudioPCMBuffer) -> Void) {
        // Remove tap cũ nếu có
        inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async { self.isRecording = false; self.inputLevel = 0 }

        audioBufferCallback = bufferCallback
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
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
        ensureEngineRunning()
        DispatchQueue.main.async { self.isRecording = true }
    }

    func stopRecording() {
        inputNode.removeTap(onBus: 0)
        DispatchQueue.main.async {
            self.isRecording = false
            self.inputLevel = 0
        }
    }

    func stopEngineForPlayback() {
        stopRecording()
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
