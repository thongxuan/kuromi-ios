import Foundation
import Combine

enum ValidationState {
    case idle
    case checking
    case success
    case failure(String)
}

class SetupViewModel: ObservableObject {
    @Published var gatewayURL: String = ""
    @Published var gatewayToken: String = ""
    @Published var deepgramAPIKey: String = ""
    @Published var openAIKey: String = ""
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    @Published var deepgramValidation: ValidationState = .idle
    @Published var openAIValidation: ValidationState = .idle

    var isEditMode: Bool = false
    private var cancellables = Set<AnyCancellable>()

    init(isEditMode: Bool = false) {
        self.isEditMode = isEditMode
        if let settings = AppSettings.load() {
            gatewayURL = settings.gatewayURL
            gatewayToken = settings.gatewayToken
            deepgramAPIKey = settings.deepgramAPIKey
            openAIKey = settings.openAIKey
        }

        $deepgramAPIKey
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] key in
                guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
                    self?.deepgramValidation = .idle; return
                }
                Task { await self?.validateDeepgram(key: key) }
            }
            .store(in: &cancellables)

        $openAIKey
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] key in
                guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
                    self?.openAIValidation = .idle; return
                }
                Task { await self?.validateOpenAI(key: key) }
            }
            .store(in: &cancellables)
    }

    var isValid: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !deepgramAPIKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !openAIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canContinue: Bool {
        guard isValid else { return false }
        if case .failure = deepgramValidation { return false }
        if case .failure = openAIValidation { return false }
        return true
    }

    @MainActor
    func validateDeepgram(key: String) async {
        deepgramValidation = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
            request.setValue("Token \(key.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            deepgramValidation = status == 200 ? .success : .failure("Invalid key (HTTP \(status))")
        } catch {
            deepgramValidation = .failure("Connection error")
        }
    }

    @MainActor
    func validateOpenAI(key: String) async {
        openAIValidation = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            request.setValue("Bearer \(key.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            openAIValidation = status == 200 ? .success : .failure("Invalid key (HTTP \(status))")
        } catch {
            openAIValidation = .failure("Connection error")
        }
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
            ttsAPIKey: "",
            selectedVoiceID: "",
            selectedVoiceName: "",
            sttLanguage: "vi",
            wakeWord: "hey kuromi",
            wakeWordSamples: [],
            openAIKey: "",
            ttsVoice: "nova"
        )
        settings.gatewayURL = gatewayURL.trimmingCharacters(in: .whitespaces)
        settings.gatewayToken = gatewayToken.trimmingCharacters(in: .whitespaces)
        settings.deepgramAPIKey = deepgramAPIKey.trimmingCharacters(in: .whitespaces)
        settings.openAIKey = openAIKey.trimmingCharacters(in: .whitespaces)
        settings.save()
        return settings
    }
}
