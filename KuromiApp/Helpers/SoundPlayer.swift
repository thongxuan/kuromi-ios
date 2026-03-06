import AVFoundation

/// Plays UI beep sounds via AVAudioPlayer with .ambient session —
/// follows system media volume, does not interfere with recording session.
class SoundPlayer: NSObject {
    private static var player: AVAudioPlayer?

    static func playStart(completion: (() -> Void)? = nil) {
        play(named: "start_beep", completion: completion)
    }

    static func playStop(completion: (() -> Void)? = nil) {
        play(named: "stop_beep", completion: completion)
    }

    static func play(named name: String, completion: (() -> Void)? = nil) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            print("[sound] missing \(name).wav — falling back")
            completion?()
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            // Deactivate current session first (e.g. playAndRecord) so .ambient takes effect
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            print("[sound] session category=\(session.category.rawValue) volume=\(session.outputVolume)")
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.prepareToPlay()
            player?.play()
            print("[sound] playing \(name)")
            if let completion {
                let duration = player?.duration ?? 0.2
                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) {
                    completion()
                }
            }
        } catch {
            print("[sound] error playing \(name): \(error)")
            completion?()
        }
    }
}
