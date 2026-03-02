import Foundation

struct VoiceOption: Identifiable, Codable {
    let voice_id: String
    let name: String
    var labels: [String: String]?
    var preview_url: String?
    var category: String?
    var description: String?

    var id: String { voice_id }

    var categoryLabel: String {
        labels?["accent"] ?? labels?["description"] ?? category ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case voice_id, name, labels, preview_url, category, description
    }
}

struct VoicesResponse: Codable {
    let voices: [VoiceOption]
}
