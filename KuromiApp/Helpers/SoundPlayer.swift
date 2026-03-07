import AudioToolbox

/// System sound player for chat state transitions.
/// Uses AudioServicesPlaySystemSound which works alongside AVAudioEngine
/// without requiring engine stop/restart.
enum SoundPlayer {
    /// Play start recording sound (system sound 1111 - begin_record.caf).
    static func playStart(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSound(1111)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completion() }
        }
    }

    /// Play stop recording sound (system sound 1110 - end_record.caf).
    static func playStop(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSound(1110)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { completion() }
        }
    }
}
