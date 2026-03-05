import Foundation

struct AppSettings: Codable {
    var gatewayURL: String
    var gatewayToken: String

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
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
