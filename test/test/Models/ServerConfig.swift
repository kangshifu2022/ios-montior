import Foundation

struct ServerConfig: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var host: String
    var port: Int = 22
    var username: String
    var password: String
    
    init(id: UUID = UUID(), name: String = "", host: String = "",
         port: Int = 22, username: String = "", password: String = "") {
        self.id = id
        self.name = name.isEmpty ? host : name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }
}
