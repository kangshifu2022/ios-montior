import Foundation

struct AlertSettings: Codable, Hashable, Sendable {
    var barkURL: String = ""

    init(barkURL: String = "") {
        self.barkURL = barkURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
