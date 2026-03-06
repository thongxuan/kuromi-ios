import AudioToolbox
import AVFoundation

enum SoundPlayer {
    static func playStart(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            AudioServicesPlaySystemSound(1111)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completion?()
            }
        }
    }

    static func playStop(completion: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            AudioServicesPlaySystemSound(1110)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completion?()
            }
        }
    }
}
