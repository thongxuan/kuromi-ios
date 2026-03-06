import AudioToolbox

enum SoundPlayer {
    static func playStart(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSound(1111)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { completion() }
        }
    }

    static func playStop(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSound(1110)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { completion() }
        }
    }
}
