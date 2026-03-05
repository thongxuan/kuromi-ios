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
        }
    }

    var canContinue: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save() -> AppSettings? {
        guard canContinue else { errorMessage = "Gateway URL is required"; return nil }
        errorMessage = ""
        let s = AppSettings(
            gatewayURL: gatewayURL.trimmingCharacters(in: .whitespaces),
            gatewayToken: gatewayToken.trimmingCharacters(in: .whitespaces),
            sttLanguage: sttLanguage,
            wakePhrase: wakePhrase.trimmingCharacters(in: .whitespaces).lowercased()
        )
        s.save()
        return s
    }

    func reloadSettings() {}
}
