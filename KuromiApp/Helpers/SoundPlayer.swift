import AudioToolbox
import AVFoundation

enum SoundPlayer {
    static func playStart(completion: (() -> Void)? = nil) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        AudioServicesPlaySystemSoundWithCompletion(1111) { completion?() }
    }

    static func playStop(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSound(1110)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { completion() }
        }
    }
}
