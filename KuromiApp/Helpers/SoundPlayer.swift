import AudioToolbox

enum SoundPlayer {
    static func playStart(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSoundWithCompletion(1111) { completion?() }
    }

    static func playStop(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSoundWithCompletion(1110) { completion?() }
    }
}
