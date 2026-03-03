import Foundation

struct AppSettings: Codable {
    var gatewayURL: String
    var gatewayToken: String
    var selectedVoiceID: String
    var selectedVoiceName: String
    var sttLanguage: String
    var wakeWord: String
    var wakeWordSamples: [String]
    var ttsVoice: String

    // Provider selection
    var selectedSTTProvider: STTProvider = .deepgram
    var selectedTTSProvider: TTSProvider = .openai

    // Provider configs (keyed by rawValue)
    var sttConfigs: [String: ProviderConfig] = [:]
    var ttsConfigs: [String: ProviderConfig] = [:]

    // Backward compat
    var deepgramAPIKey: String = ""
    var ttsAPIKey: String = ""
    var openAIKey: String = ""

    static let defaultsKey = "kuromi_settings"

    // Current active STT config
    var activeSSTConfig: ProviderConfig {
        sttConfigs[selectedSTTProvider.rawValue] ?? ProviderConfig()
    }

    // Current active TTS config
    var activeTTSConfig: ProviderConfig {
        ttsConfigs[selectedTTSProvider.rawValue] ?? ProviderConfig()
    }

    static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return nil
        }
        // Load sensitive keys from Keychain for each provider
        for provider in STTProvider.allCases {
            let key = "kuromi_stt_\(provider.rawValue)"
            if let apiKey = KeychainHelper.load(key: key), !apiKey.isEmpty {
                var config = settings.sttConfigs[provider.rawValue] ?? ProviderConfig()
                config.apiKey = apiKey
                settings.sttConfigs[provider.rawValue] = config
            }
        }
        for provider in TTSProvider.allCases {
            let key = "kuromi_tts_\(provider.rawValue)"
            if let apiKey = KeychainHelper.load(key: key), !apiKey.isEmpty {
                var config = settings.ttsConfigs[provider.rawValue] ?? ProviderConfig()
                config.apiKey = apiKey
                settings.ttsConfigs[provider.rawValue] = config
            }
        }
        return settings
    }

    func save() {
        var toSave = self
        // Save API keys to Keychain, clear from UserDefaults
        for provider in STTProvider.allCases {
            let key = "kuromi_stt_\(provider.rawValue)"
            if let apiKey = toSave.sttConfigs[provider.rawValue]?.apiKey {
                KeychainHelper.save(key: key, value: apiKey)
                toSave.sttConfigs[provider.rawValue]?.apiKey = ""
            }
        }
        for provider in TTSProvider.allCases {
            let key = "kuromi_tts_\(provider.rawValue)"
            if let apiKey = toSave.ttsConfigs[provider.rawValue]?.apiKey {
                KeychainHelper.save(key: key, value: apiKey)
                toSave.ttsConfigs[provider.rawValue]?.apiKey = ""
            }
        }
        toSave.deepgramAPIKey = ""
        toSave.ttsAPIKey = ""
        toSave.openAIKey = ""

        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: AppSettings.defaultsKey)
        }
    }
}
