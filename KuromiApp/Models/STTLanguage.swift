import Foundation

struct STTLanguage: Identifiable, Hashable {
    let code: String
    let name: String
    let flag: String

    var id: String { code }

    static func from(code: String) -> STTLanguage {
        popular.first { $0.code == code } ?? STTLanguage(code: code, name: code, flag: "🌐")
    }

    static let popular: [STTLanguage] = [
        STTLanguage(code: "vi", name: "Tiếng Việt", flag: "🇻🇳"),
        STTLanguage(code: "en", name: "English", flag: "🇺🇸"),
        STTLanguage(code: "en-GB", name: "English (UK)", flag: "🇬🇧"),
        STTLanguage(code: "zh", name: "中文", flag: "🇨🇳"),
        STTLanguage(code: "zh-TW", name: "中文 (繁體)", flag: "🇹🇼"),
        STTLanguage(code: "ja", name: "日本語", flag: "🇯🇵"),
        STTLanguage(code: "ko", name: "한국어", flag: "🇰🇷"),
        STTLanguage(code: "th", name: "ภาษาไทย", flag: "🇹🇭"),
        STTLanguage(code: "id", name: "Bahasa Indonesia", flag: "🇮🇩"),
        STTLanguage(code: "fr", name: "Français", flag: "🇫🇷"),
        STTLanguage(code: "de", name: "Deutsch", flag: "🇩🇪"),
        STTLanguage(code: "es", name: "Español", flag: "🇪🇸"),
        STTLanguage(code: "pt", name: "Português", flag: "🇧🇷"),
        STTLanguage(code: "it", name: "Italiano", flag: "🇮🇹"),
        STTLanguage(code: "ru", name: "Русский", flag: "🇷🇺"),
        STTLanguage(code: "ar", name: "العربية", flag: "🇸🇦"),
        STTLanguage(code: "hi", name: "हिन्दी", flag: "🇮🇳"),
        STTLanguage(code: "nl", name: "Nederlands", flag: "🇳🇱"),
        STTLanguage(code: "pl", name: "Polski", flag: "🇵🇱"),
        STTLanguage(code: "tr", name: "Türkçe", flag: "🇹🇷"),
    ]
}
