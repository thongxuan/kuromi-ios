import Foundation

enum MessageRole {
    case user
    case assistant
}

struct Message: Identifiable {
    let id = UUID()
    let role: MessageRole
    var text: String
    let timestamp: Date

    init(role: MessageRole, text: String) {
        self.role = role
        self.text = text
        self.timestamp = Date()
    }
}
