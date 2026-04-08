import Foundation

enum ServerMonitorDiagnosticLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case info
    case warning
    case error

    nonisolated var title: String {
        switch self {
        case .info:
            return "INFO"
        case .warning:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }
}

struct ServerMonitorDiagnosticEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var timestamp: Date
    var level: ServerMonitorDiagnosticLevel
    var category: String
    var serverName: String?
    var serverHost: String?
    var message: String

    nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: ServerMonitorDiagnosticLevel,
        category: String,
        serverName: String? = nil,
        serverHost: String? = nil,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.serverName = serverName
        self.serverHost = serverHost
        self.message = message
    }

    nonisolated var serverSummary: String? {
        switch (serverName, serverHost) {
        case let (name?, host?) where !name.isEmpty && !host.isEmpty:
            return "\(name) · \(host)"
        case let (name?, _) where !name.isEmpty:
            return name
        case let (_, host?) where !host.isEmpty:
            return host
        default:
            return nil
        }
    }
}
