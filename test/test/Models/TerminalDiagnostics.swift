import Foundation

enum TerminalDiagnosticLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case info
    case warning
    case error

    var title: String {
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

struct TerminalDiagnosticEntry: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var timestamp: Date
    var level: TerminalDiagnosticLevel
    var category: String
    var serverName: String?
    var serverHost: String?
    var sessionName: String?
    var message: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: TerminalDiagnosticLevel,
        category: String,
        serverName: String? = nil,
        serverHost: String? = nil,
        sessionName: String? = nil,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.serverName = serverName
        self.serverHost = serverHost
        self.sessionName = sessionName
        self.message = message
    }

    var serverSummary: String? {
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
