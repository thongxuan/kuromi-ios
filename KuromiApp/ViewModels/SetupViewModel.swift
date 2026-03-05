import Foundation

enum ValidationState {
    case idle, checking, success
    case failure(String)
}

class SetupViewModel: ObservableObject {
    @Published var gatewayURL: String = ""
    @Published var gatewayToken: String = ""
    @Published var errorMessage: String = ""

    var isEditMode: Bool = false

    init(isEditMode: Bool = false) {
        self.isEditMode = isEditMode
        if let s = AppSettings.load() {
            gatewayURL = s.gatewayURL
            gatewayToken = s.gatewayToken
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
            gatewayToken: gatewayToken.trimmingCharacters(in: .whitespaces)
        )
        s.save()
        return s
    }

    func reloadSettings() {}
}
