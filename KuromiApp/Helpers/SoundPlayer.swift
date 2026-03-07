import AudioToolbox

/// System sound player for chat state transitions.
/// Uses AudioServicesPlaySystemSound which works alongside AVAudioEngine
/// without requiring engine stop/restart.
///
/// Sound feedback rules:
/// - playStartBeep(): ONLY on wake word detection or orb tap from idle (IDLE → LISTENING)
/// - playStopBeep(): ONLY on triggerStop() / stop word detection (LISTENING → IDLE)
/// - NO sound on auto-resume after TTS finishes (silent LISTENING resume)
enum SoundPlayer {
    /// Play start recording beep (system sound 1111 - begin_record.caf).
    /// Called ONLY when wake word detected or orb tapped from idle state.
    /// Sound plays first, then 0.5s delay before completion callback.
    static func playStartBeep(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSound(1111)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { completion() }
        }
    }

    /// Play stop recording beep (system sound 1110 - end_record.caf).
    /// Called ONLY when user explicitly stops via orb tap or stop phrase.
    /// Sound plays first, then 0.5s delay before completion callback.
    static func playStopBeep(completion: (() -> Void)? = nil) {
        AudioServicesPlaySystemSound(1110)
        if let completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { completion() }
        }
    }
}
