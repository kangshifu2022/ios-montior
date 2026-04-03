import Foundation

struct ServerConfig: Identifiable, Codable, Hashable, Sendable {
    static let defaultBarkTestTitleTemplate = "{server} 测试通知"
    static let defaultBarkTestBodyTemplate = "当前 CPU 占用率 {cpu}%"
    static let defaultBarkAlertTitleTemplate = "{server} CPU 告警"
    static let defaultBarkAlertBodyTemplate = "CPU 占用率 {cpu}% ，已超过阈值 {threshold}%"

    var id = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String
    var password: String
    var barkURL: String = ""
    var cpuAlertEnabled: Bool = false
    var cpuAlertThreshold: Int = 90
    var cpuAlertCooldownMinutes: Int = 10
    var barkTestTitleTemplate: String = ServerConfig.defaultBarkTestTitleTemplate
    var barkTestBodyTemplate: String = ServerConfig.defaultBarkTestBodyTemplate
    var barkAlertTitleTemplate: String = ServerConfig.defaultBarkAlertTitleTemplate
    var barkAlertBodyTemplate: String = ServerConfig.defaultBarkAlertBodyTemplate
    
    init(id: UUID = UUID(), name: String = "", host: String = "",
         port: Int = 22, username: String = "", password: String = "",
         barkURL: String = "", cpuAlertEnabled: Bool = false,
         cpuAlertThreshold: Int = 90, cpuAlertCooldownMinutes: Int = 10,
         barkTestTitleTemplate: String = ServerConfig.defaultBarkTestTitleTemplate,
         barkTestBodyTemplate: String = ServerConfig.defaultBarkTestBodyTemplate,
         barkAlertTitleTemplate: String = ServerConfig.defaultBarkAlertTitleTemplate,
         barkAlertBodyTemplate: String = ServerConfig.defaultBarkAlertBodyTemplate) {
        self.id = id
        self.name = name.isEmpty ? host : name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.barkURL = barkURL
        self.cpuAlertEnabled = cpuAlertEnabled
        self.cpuAlertThreshold = cpuAlertThreshold
        self.cpuAlertCooldownMinutes = cpuAlertCooldownMinutes
        self.barkTestTitleTemplate = ServerConfig.normalizedTemplate(
            barkTestTitleTemplate,
            fallback: ServerConfig.defaultBarkTestTitleTemplate
        )
        self.barkTestBodyTemplate = ServerConfig.normalizedTemplate(
            barkTestBodyTemplate,
            fallback: ServerConfig.defaultBarkTestBodyTemplate
        )
        self.barkAlertTitleTemplate = ServerConfig.normalizedTemplate(
            barkAlertTitleTemplate,
            fallback: ServerConfig.defaultBarkAlertTitleTemplate
        )
        self.barkAlertBodyTemplate = ServerConfig.normalizedTemplate(
            barkAlertBodyTemplate,
            fallback: ServerConfig.defaultBarkAlertBodyTemplate
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case host
        case port
        case username
        case password
        case barkURL
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
        host = try container.decodeIfPresent(String.self, forKey: .host) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? host
        if name.isEmpty {
            name = host
        }
        port = try container.decodeIfPresent(Int.self, forKey: .port) ?? 22
        username = try container.decodeIfPresent(String.self, forKey: .username) ?? ""
        password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        barkURL = try container.decodeIfPresent(String.self, forKey: .barkURL) ?? ""
        cpuAlertEnabled = try container.decodeIfPresent(Bool.self, forKey: .cpuAlertEnabled) ?? false
        cpuAlertThreshold = try container.decodeIfPresent(Int.self, forKey: .cpuAlertThreshold) ?? 90
        cpuAlertCooldownMinutes = try container.decodeIfPresent(Int.self, forKey: .cpuAlertCooldownMinutes) ?? 10
        barkTestTitleTemplate = ServerConfig.normalizedTemplate(
            try container.decodeIfPresent(String.self, forKey: .barkTestTitleTemplate),
            fallback: ServerConfig.defaultBarkTestTitleTemplate
        )
        barkTestBodyTemplate = ServerConfig.normalizedTemplate(
            try container.decodeIfPresent(String.self, forKey: .barkTestBodyTemplate),
            fallback: ServerConfig.defaultBarkTestBodyTemplate
        )
        barkAlertTitleTemplate = ServerConfig.normalizedTemplate(
            try container.decodeIfPresent(String.self, forKey: .barkAlertTitleTemplate),
            fallback: ServerConfig.defaultBarkAlertTitleTemplate
        )
        barkAlertBodyTemplate = ServerConfig.normalizedTemplate(
            try container.decodeIfPresent(String.self, forKey: .barkAlertBodyTemplate),
            fallback: ServerConfig.defaultBarkAlertBodyTemplate
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(username, forKey: .username)
        try container.encode(password, forKey: .password)
        try container.encode(barkURL, forKey: .barkURL)
        try container.encode(cpuAlertEnabled, forKey: .cpuAlertEnabled)
        try container.encode(cpuAlertThreshold, forKey: .cpuAlertThreshold)
        try container.encode(cpuAlertCooldownMinutes, forKey: .cpuAlertCooldownMinutes)
        try container.encode(barkTestTitleTemplate, forKey: .barkTestTitleTemplate)
        try container.encode(barkTestBodyTemplate, forKey: .barkTestBodyTemplate)
        try container.encode(barkAlertTitleTemplate, forKey: .barkAlertTitleTemplate)
        try container.encode(barkAlertBodyTemplate, forKey: .barkAlertBodyTemplate)
    }

    private static func normalizedTemplate(_ value: String?, fallback: String) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
