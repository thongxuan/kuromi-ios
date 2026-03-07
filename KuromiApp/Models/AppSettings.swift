import Foundation
import Speech

struct AppSettings: Codable {
    var gatewayURL: String
    var gatewayToken: String
    var sttLanguage: String = "vi"
    var wakePhrase: String = ""
    var stopPhrase: String = ""
    var useOnDeviceVoice: Bool = false
    var onDeviceVoiceId: String = ""
    var useSpeaker: Bool = false

    static let defaultsKey = "kuromi_settings"

    /// true on A14+ (iPhone 12+) — SFSpeechRecognizer.supportsOnDeviceRecognition
    static var deviceSupportsOnDeviceVoice: Bool {
        SFSpeechRecognizer(locale: Locale(identifier: "en-US"))?.supportsOnDeviceRecognition ?? false
    }

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    static func loadOrDefault(gatewayURL: String = "", gatewayToken: String = "") -> AppSettings {
        if let s = load() { return s }
        return AppSettings(
            gatewayURL: gatewayURL,
            gatewayToken: gatewayToken,
            useOnDeviceVoice: deviceSupportsOnDeviceVoice
        )
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.defaultsKey)
        }
    }
}
