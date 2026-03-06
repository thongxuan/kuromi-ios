import Foundation
import AVFoundation

class OnDeviceTTSService: NSObject {
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?

    var useLoudSpeaker: Bool = false
    private let synthesizer = AVSpeechSynthesizer()
    private var voiceId: String = ""
    private var language: String = "en"

    private static let emojiPattern = try! NSRegularExpression(
        pattern: "[\\p{Emoji_Presentation}\\p{Extended_Pictographic}]",
        options: []
    )

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(text: String, voiceId: String, language: String) {
        self.voiceId = voiceId
        self.language = language

        let cleaned = Self.stripEmoji(text)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onFinish?()
            return
        }

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: cleaned)

        utterance.voice = resolveVoice(voiceId: voiceId, language: language)

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP])
        try? session.setActive(true)
        try? session.overrideOutputAudioPort(useLoudSpeaker ? .speaker : .none)

        onStart?()
        synthesizer.speak(utterance)
        print("[onDeviceTTS] speaking: \(cleaned.prefix(50))")
    }

    /// Resolve voice with fallback: preferred → compact same lang → any same lang → nil
    private func resolveVoice(voiceId: String, language: String) -> AVSpeechSynthesisVoice? {
        let langPrefix = String(language.prefix(2))
        let allForLang = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(langPrefix) }
        let compacts = allForLang.filter { $0.quality == .default }

        // Try preferred voice
        if !voiceId.isEmpty, let preferred = AVSpeechSynthesisVoice(identifier: voiceId) {
            // Verify it's usable: compact voices always work; enhanced/premium may not be downloaded
            if preferred.quality == .default { return preferred }
            // For enhanced/premium: attempt to use — if MobileAsset warns, iOS falls back anyway
            // but we proactively fallback to best compact to avoid silence
            let testOk = compacts.contains { $0.language == preferred.language }
            if !testOk { return preferred } // no compact alternative, try anyway
            // Use compact with same locale if available, else any compact
            return compacts.first { $0.language == preferred.language } ?? compacts.first ?? preferred
        }
        // No voiceId — use best compact
        return compacts.first ?? AVSpeechSynthesisVoice(language: language)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    private static func stripEmoji(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return emojiPattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}

extension OnDeviceTTSService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.onFinish?()
            print("[onDeviceTTS] finished")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.onFinish?()
            print("[onDeviceTTS] cancelled")
        }
    }
}
