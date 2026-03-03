import Foundation

struct AppSettings: Codable {
    var gatewayURL: String
    var gatewayToken: String
    var deepgramAPIKey: String
    var elevenLabsAPIKey: String
    var selectedVoiceID: String
    var selectedVoiceName: String
    var sttLanguage: String
    var wakeWord: String
    var wakeWordSamples: [String]
    var openAIKey: String        // OpenAI API key cho TTS
    var ttsVoice: String         // OpenAI voice: nova, alloy, shimmer...

    static let defaultsKey = "kuromi_settings"
    static let keychainDeepgramKey = "kuromi_deepgram_key"
    static let keychainElevenLabsKey = "kuromi_elevenlabs_key"
    static let keychainOpenAIKey = "kuromi_openai_key"

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        // Load sensitive keys from Keychain
        settings.deepgramAPIKey = KeychainHelper.load(key: keychainDeepgramKey) ?? settings.deepgramAPIKey
        settings.elevenLabsAPIKey = KeychainHelper.load(key: keychainElevenLabsKey) ?? settings.elevenLabsAPIKey
        settings.openAIKey = KeychainHelper.load(key: keychainOpenAIKey) ?? settings.openAIKey
        return settings
    }

    func save() {
        var toSave = self
        // Save sensitive keys to Keychain
        KeychainHelper.save(key: AppSettings.keychainDeepgramKey, value: deepgramAPIKey)
        KeychainHelper.save(key: AppSettings.keychainElevenLabsKey, value: elevenLabsAPIKey)
        KeychainHelper.save(key: AppSettings.keychainOpenAIKey, value: openAIKey)
        toSave.deepgramAPIKey = ""
        toSave.elevenLabsAPIKey = ""
        toSave.openAIKey = ""

        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: AppSettings.defaultsKey)
        }
    }
}
