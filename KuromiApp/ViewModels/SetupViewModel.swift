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
    @Published var elevenLabsAPIKey: String = ""
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false

    @Published var deepgramValidation: ValidationState = .idle
    @Published var elevenLabsValidation: ValidationState = .idle

    var isEditMode: Bool = false

    // Debounce timers
    private var deepgramTimer: Timer?
    private var elevenLabsTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(isEditMode: Bool = false) {
        self.isEditMode = isEditMode
        if let settings = AppSettings.load() {
            gatewayURL = settings.gatewayURL
            gatewayToken = settings.gatewayToken
            deepgramAPIKey = settings.deepgramAPIKey
            elevenLabsAPIKey = settings.elevenLabsAPIKey
        }

        // Auto-validate when keys change (debounced)
        $deepgramAPIKey
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] key in
                guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
                    self?.deepgramValidation = .idle; return
                }
                Task { await self?.validateDeepgram(key: key) }
            }
            .store(in: &cancellables)

        $elevenLabsAPIKey
            .debounce(for: .seconds(0.8), scheduler: RunLoop.main)
            .sink { [weak self] key in
                guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
                    self?.elevenLabsValidation = .idle; return
                }
                Task { await self?.validateElevenLabs(key: key) }
            }
            .store(in: &cancellables)
    }

    var isValid: Bool {
        !gatewayURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !deepgramAPIKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !elevenLabsAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var canContinue: Bool {
        guard isValid else { return false }
        if case .failure = deepgramValidation { return false }
        if case .failure = elevenLabsValidation { return false }
        return true
    }

    // MARK: - Validation

    @MainActor
    func validateDeepgram(key: String) async {
        deepgramValidation = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
            request.setValue("Token \(key.trimmingCharacters(in: .whitespaces))", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                deepgramValidation = .success
            } else {
                deepgramValidation = .failure("Invalid key (HTTP \(status))")
            }
        } catch {
            deepgramValidation = .failure("Connection error")
        }
    }

    @MainActor
    func validateElevenLabs(key: String) async {
        elevenLabsValidation = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/user")!)
            request.setValue(key.trimmingCharacters(in: .whitespaces), forHTTPHeaderField: "xi-api-key")
            request.timeoutInterval = 8
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                elevenLabsValidation = .success
            } else {
                elevenLabsValidation = .failure("Invalid key (HTTP \(status))")
            }
        } catch {
            elevenLabsValidation = .failure("Connection error")
        }
    }

    // MARK: - Save

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
            sttLanguage: "vi",
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
