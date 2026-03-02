import Foundation
import Combine

class SetupViewModel: ObservableObject {
    @Published var gatewayURL: String = ""
    @Published var gatewayToken: String = ""
    @Published var deepgramAPIKey: String = ""
    @Published var elevenLabsAPIKey: String = ""
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    var isEditMode: Bool = false

    init(isEditMode: Bool = false) {
        self.isEditMode = isEditMode
        if let settings = AppSettings.load() {
            gatewayURL = settings.gatewayURL
            gatewayToken = settings.gatewayToken
            deepgramAPIKey = settings.deepgramAPIKey
            elevenLabsAPIKey = settings.elevenLabsAPIKey
        }
    }

    var isValid: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !deepgramAPIKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !elevenLabsAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func save() -> AppSettings? {
        guard isValid else {
            errorMessage = "Please fill in all fields"
            return nil
        }
        errorMessage = ""
        var settings = AppSettings.load() ?? AppSettings(
            gatewayURL: "",
            gatewayToken: "",
            deepgramAPIKey: "",
            elevenLabsAPIKey: "",
            selectedVoiceID: "",
            selectedVoiceName: "",
            wakeWord: "hey kuromi",
            wakeWordSamples: []
        )
        settings.gatewayURL = gatewayURL.trimmingCharacters(in: .whitespaces)
        settings.gatewayToken = gatewayToken.trimmingCharacters(in: .whitespaces)
        settings.deepgramAPIKey = deepgramAPIKey.trimmingCharacters(in: .whitespaces)
        settings.elevenLabsAPIKey = elevenLabsAPIKey.trimmingCharacters(in: .whitespaces)
        settings.save()
        return settings
    }
}
