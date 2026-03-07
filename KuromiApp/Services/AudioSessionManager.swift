import AVFoundation
import Foundation

/// Centralized AVAudioSession management.
/// Handles audio session setup and route changes without restarting the audio engine.
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private init() {
        setupRouteChangeObserver()
    }

    // MARK: - Public API

    /// Configure audio session for voice chat (mic + speaker).
    func setupForChat(loudSpeaker: Bool = false) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,  // enables iOS built-in AEC (acoustic echo cancellation)
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true)
            try session.overrideOutputAudioPort(loudSpeaker ? .speaker : .none)
            print("[AudioSession] configured for chat, loudSpeaker=\(loudSpeaker)")
        } catch {
            print("[AudioSession] setup error: \(error)")
        }
    }

    /// Toggle speaker output routing.
    func setSpeaker(_ loud: Bool) {
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(loud ? .speaker : .none)
            print("[AudioSession] speaker override: \(loud)")
        } catch {
            print("[AudioSession] speaker error: \(error)")
        }
    }

    /// Deactivate audio session (when leaving ChatView).
    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("[AudioSession] deactivated")
        } catch {
            print("[AudioSession] deactivate error: \(error)")
        }
    }

    // MARK: - Route Change Handling

    /// Callback when headphones connect (to disable loud speaker).
    var onHeadphonesConnected: (() -> Void)?

    /// Callback when headphones disconnect (to restore speaker state).
    var onHeadphonesDisconnected: (() -> Void)?

    private func setupRouteChangeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let routeReason = AVAudioSession.RouteChangeReason(rawValue: reason) else { return }

        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let hasHeadphones = outputs.contains {
            $0.portType == .headphones ||
            $0.portType == .bluetoothA2DP ||
            $0.portType == .bluetoothHFP
        }

        DispatchQueue.main.async {
            switch routeReason {
            case .newDeviceAvailable:
                if hasHeadphones {
                    print("[AudioSession] headphones connected")
                    self.onHeadphonesConnected?()
                }
            case .oldDeviceUnavailable:
                if !hasHeadphones {
                    print("[AudioSession] headphones disconnected")
                    self.onHeadphonesDisconnected?()
                }
            default:
                break
            }
        }
    }

    // MARK: - Helpers

    var currentSampleRate: Double {
        AVAudioSession.sharedInstance().sampleRate
    }

    var hasHeadphones: Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains {
            $0.portType == .headphones ||
            $0.portType == .bluetoothA2DP ||
            $0.portType == .bluetoothHFP
        }
    }

    /// Reduce mic input gain during TTS playback to suppress echo (loud speaker mode).
    /// Only effective if device supports input gain adjustment.
    func setMicGain(_ gain: Float) {
        let session = AVAudioSession.sharedInstance()
        guard session.isInputGainSettable else {
            print("[AudioSession] inputGain not settable on this device")
            return
        }
        do {
            try session.setInputGain(gain)
            print("[AudioSession] inputGain set to \(gain)")
        } catch {
            print("[AudioSession] setInputGain error: \(error)")
        }
    }
}
