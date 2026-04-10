import Foundation

struct ServerConfig: Identifiable, Codable, Hashable, Sendable {
    static let allGroupName = "All"
    static let legacyPlaceholderCreatedAt = Date(timeIntervalSince1970: 0)

    var id = UUID()
    var createdAt: Date
    var name: String
    var groupName: String
    var host: String
    var port: Int = 22
    var username: String
    var password: String
    var barkURL: String = ""
    var alertConfiguration: AlertConfiguration = AlertConfiguration()

    init(id: UUID = UUID(), createdAt: Date = Date(), name: String = "", groupName: String = ServerConfig.allGroupName, host: String = "",
         port: Int = 22, username: String = "", password: String = "",
         barkURL: String = "",
         alertConfiguration: AlertConfiguration = AlertConfiguration()) {
        self.id = id
        self.createdAt = createdAt
        self.name = name.isEmpty ? host : name
        self.groupName = Self.normalizedGroupName(groupName)
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.barkURL = barkURL
        self.alertConfiguration = alertConfiguration
    }

    var resolvedGroupName: String {
        Self.normalizedGroupName(groupName)
    }

    static func normalizedGroupName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return allGroupName
        }

        return trimmed.caseInsensitiveCompare(allGroupName) == .orderedSame ? allGroupName : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case name
        case groupName
        case host
        case port
        case username
        case password
        case barkURL
        case alertConfiguration
        case cpuAlertEnabled
        case cpuAlertThreshold
        case cpuAlertCooldownMinutes
        case barkTestTitleTemplate
        case barkTestBodyTemplate
        case barkAlertTitleTemplate
        case barkAlertBodyTemplate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyPlaceholderCreatedAt
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? host
        if name.isEmpty {
            name = host
        }
        groupName = Self.normalizedGroupName(
            try container.decodeIfPresent(String.self, forKey: .groupName) ?? Self.allGroupName
        )
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        barkURL = try container.decodeIfPresent(String.self, forKey: .barkURL) ?? ""
        if let decodedConfiguration = try container.decodeIfPresent(AlertConfiguration.self, forKey: .alertConfiguration) {
            alertConfiguration = decodedConfiguration
        } else {
            let legacyEnabled = try container.decodeIfPresent(Bool.self, forKey: .cpuAlertEnabled) ?? false
            let legacyThreshold = try container.decodeIfPresent(Int.self, forKey: .cpuAlertThreshold) ?? 90
            let legacyCooldown = try container.decodeIfPresent(Int.self, forKey: .cpuAlertCooldownMinutes) ?? 10
            alertConfiguration = AlertConfiguration.legacy(
                cpuAlertEnabled: legacyEnabled,
                cpuAlertThreshold: legacyThreshold,
                cpuAlertCooldownMinutes: legacyCooldown
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(name, forKey: .name)
        try container.encode(Self.normalizedGroupName(groupName), forKey: .groupName)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(barkURL, forKey: .barkURL)
        try container.encode(alertConfiguration, forKey: .alertConfiguration)
    }
}
