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

        // Try specific voice ID first, fall back to language default
        if !voiceId.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            // Use language code to find best voice
            let langCode = String(language.prefix(2))
            let voices = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language.hasPrefix(langCode) }
                .sorted { $0.quality.rawValue > $1.quality.rawValue }
            utterance.voice = voices.first ?? AVSpeechSynthesisVoice(language: language)
        }

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
