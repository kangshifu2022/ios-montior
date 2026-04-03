import Foundation

struct ServerConfig: Identifiable, Codable, Hashable, Sendable {
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
    
    init(id: UUID = UUID(), name: String = "", host: String = "",
         port: Int = 22, username: String = "", password: String = "",
         barkURL: String = "", cpuAlertEnabled: Bool = false,
         cpuAlertThreshold: Int = 90, cpuAlertCooldownMinutes: Int = 10) {
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
    }
}
