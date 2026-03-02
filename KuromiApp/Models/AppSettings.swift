import Foundation

struct AppSettings: Codable {
    var gatewayURL: String
    var gatewayToken: String
    var deepgramAPIKey: String
    var elevenLabsAPIKey: String
    var selectedVoiceID: String
    var selectedVoiceName: String
    var sttLanguage: String  // Deepgram language code, e.g. "vi", "en"
    var wakeWord: String
    var wakeWordSamples: [String] // base64 encoded audio samples

    static let defaultsKey = "kuromi_settings"
    static let keychainDeepgramKey = "kuromi_deepgram_key"
    static let keychainElevenLabsKey = "kuromi_elevenlabs_key"

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        // Load sensitive keys from Keychain
        settings.deepgramAPIKey = KeychainHelper.load(key: keychainDeepgramKey) ?? settings.deepgramAPIKey
        settings.elevenLabsAPIKey = KeychainHelper.load(key: keychainElevenLabsKey) ?? settings.elevenLabsAPIKey
        return settings
    }

    func save() {
        var toSave = self
        // Save sensitive keys to Keychain
        KeychainHelper.save(key: AppSettings.keychainDeepgramKey, value: deepgramAPIKey)
        KeychainHelper.save(key: AppSettings.keychainElevenLabsKey, value: elevenLabsAPIKey)
        toSave.deepgramAPIKey = ""
        toSave.elevenLabsAPIKey = ""

        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: AppSettings.defaultsKey)
        }
    }
}
