import Foundation

struct AppSettings: Codable {
    var gatewayURL: String
    var gatewayToken: String
    var sttLanguage: String = "vi"
    var wakePhrase: String = "kuromi"
    var stopPhrase: String = "dừng lại"
    var useOnDeviceSTT: Bool = false
    var useSpeaker: Bool = false
    var useOnDeviceTTS: Bool = false
    var onDeviceTTSLanguage: String = "vi-VN"
    var onDeviceTTSRate: Float = 0.5

    static let defaultsKey = "kuromi_settings"

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.defaultsKey)
        }
    }
}
