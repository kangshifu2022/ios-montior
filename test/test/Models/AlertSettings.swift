import Foundation

struct AlertSettings: Codable, Hashable, Sendable {
    var barkURL: String = ""
    var cooldownMinutes: Int = 10

    init(barkURL: String = "", cooldownMinutes: Int = 10) {
        self.barkURL = barkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cooldownMinutes = max(1, cooldownMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case barkURL
        case cooldownMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        barkURL = try container.decodeIfPresent(String.self, forKey: .barkURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        cooldownMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 10)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(barkURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: .barkURL)
        try container.encode(max(1, cooldownMinutes), forKey: .cooldownMinutes)
    }
}
