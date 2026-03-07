import Foundation

enum ValidationState {
    case idle, checking, success
    case failure(String)
}

class SetupViewModel: ObservableObject {
    @Published var gatewayURL: String = ""
    @Published var gatewayToken: String = ""
    @Published var sttLanguage: String = "vi"
    @Published var wakePhrase: String = "kuromi"
    @Published var stopPhrase: String = "dừng lại"
    @Published var useOnDeviceVoice: Bool = false
    let deviceSupportsOnDeviceVoice: Bool = AppSettings.deviceSupportsOnDeviceVoice
    @Published var onDeviceVoiceId: String = ""
    @Published var useSpeaker: Bool = false
    @Published var errorMessage: String = ""

    var isEditMode: Bool = false

    static let languages: [(code: String, name: String, flag: String)] = [
        ("vi", "Tiếng Việt", "🇻🇳"),
        ("en", "English", "🇺🇸"),
        ("ja", "日本語", "🇯🇵"),
        ("zh", "中文", "🇨🇳"),
        ("ko", "한국어", "🇰🇷"),
        ("fr", "Français", "🇫🇷"),
        ("de", "Deutsch", "🇩🇪"),
        ("es", "Español", "🇪🇸"),
    ]

    init(isEditMode: Bool = false) {
        self.isEditMode = isEditMode
        if let s = AppSettings.load() {
            gatewayURL = s.gatewayURL
            gatewayToken = s.gatewayToken
            sttLanguage = s.sttLanguage
            wakePhrase = s.wakePhrase
            stopPhrase = s.stopPhrase
            useOnDeviceVoice = s.useOnDeviceVoice
            onDeviceVoiceId = s.onDeviceVoiceId
            useSpeaker = s.useSpeaker
        } else {
            // First launch — default on-device voice based on device capability
            useOnDeviceVoice = AppSettings.deviceSupportsOnDeviceVoice
        }
    }

    var canContinue: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !wakePhrase.trimmingCharacters(in: .whitespaces).isEmpty &&
        !stopPhrase.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save() -> AppSettings? {
        guard !gatewayURL.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Gateway URL is required"; return nil }
        guard !wakePhrase.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Wake phrase is required"; return nil }
        guard !stopPhrase.trimmingCharacters(in: .whitespaces).isEmpty else { errorMessage = "Stop phrase is required"; return nil }
        errorMessage = ""
        var s = AppSettings(
            gatewayURL: gatewayURL.trimmingCharacters(in: .whitespaces),
            gatewayToken: gatewayToken.trimmingCharacters(in: .whitespaces),
            sttLanguage: sttLanguage,
            wakePhrase: wakePhrase.trimmingCharacters(in: .whitespaces).lowercased(),
            stopPhrase: stopPhrase.trimmingCharacters(in: .whitespaces).lowercased()
        )
        s.useOnDeviceVoice = useOnDeviceVoice
        s.onDeviceVoiceId = onDeviceVoiceId
        s.useSpeaker = useSpeaker
        s.save()
        return s
    }
}
