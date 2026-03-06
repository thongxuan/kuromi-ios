import AudioToolbox
import AVFoundation

enum SoundPlayer {
    static func playStart(completion: (() -> Void)? = nil) {
        // Deactivate any active audio session so system sound plays cleanly (no distortion)
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            DispatchQueue.main.async {
                if let completion {
                    AudioServicesPlaySystemSoundWithCompletion(1111) {
                        DispatchQueue.main.async { completion() }
                    }
                } else {
                    AudioServicesPlaySystemSound(1111)
                }
            }
        }
    }

    static func playStop(completion: (() -> Void)? = nil) {
        if let completion {
            AudioServicesPlaySystemSoundWithCompletion(1110) {
                DispatchQueue.main.async { completion() }
            }
        } else {
            AudioServicesPlaySystemSound(1110)
        }
    }
}
