import Foundation

enum ServerMonitorDiagnosticsStore {
    nonisolated static var didChangeNotification: Notification.Name {
        Notification.Name("serverMonitorDiagnosticsDidChange")
    }

    nonisolated private static let maxEntries = 500
    nonisolated private static let queue = DispatchQueue(label: "server.monitor.diagnostics.store")
    nonisolated private static let storageKey = "server.monitor.diagnostics.entries.v1"

    nonisolated static func record(
        _ message: String,
        level: ServerMonitorDiagnosticLevel = .info,
        category: String,
        server: ServerConfig? = nil
    ) {
        let entry = ServerMonitorDiagnosticEntry(
            level: level,
            category: category,
            serverName: server?.name,
            serverHost: server?.host,
            message: message
        )

        queue.sync {
            var entries = loadEntriesUnlocked()
            entries.append(entry)
            if entries.count > maxEntries {
                entries = Array(entries.suffix(maxEntries))
            }
            saveEntriesUnlocked(entries)
        }

        notifyDidChange()
    }

    nonisolated static func loadEntries() -> [ServerMonitorDiagnosticEntry] {
        queue.sync {
            loadEntriesUnlocked().sorted { $0.timestamp > $1.timestamp }
        }
    }

    nonisolated static func clear() {
        queue.sync {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        notifyDidChange()
    }

    nonisolated static func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let entries = loadEntries().reversed()
        guard !entries.isEmpty else {
            return "还没有监控诊断日志。"
        }

        return entries.map { entry in
            var fragments: [String] = []
            fragments.append(formatter.string(from: entry.timestamp))
            fragments.append("[\(levelTitle(for: entry.level))]")
            fragments.append("[\(entry.category)]")

            if let serverSummary = formattedServerSummary(for: entry), !serverSummary.isEmpty {
                fragments.append("[\(serverSummary)]")
            }

            fragments.append(entry.message)
            return fragments.joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    nonisolated private static func loadEntriesUnlocked() -> [ServerMonitorDiagnosticEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ServerMonitorDiagnosticEntry].self, from: data) else {
            return []
        }

        return decoded
    }

    nonisolated private static func saveEntriesUnlocked(_ entries: [ServerMonitorDiagnosticEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    nonisolated private static func levelTitle(for level: ServerMonitorDiagnosticLevel) -> String {
        switch level {
        case .info:
            return "INFO"
        case .warning:
            return "WARN"
        case .error:
            return "ERROR"
        }
    }

    nonisolated private static func formattedServerSummary(for entry: ServerMonitorDiagnosticEntry) -> String? {
        switch (entry.serverName, entry.serverHost) {
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

    nonisolated private static func notifyDidChange() {
        if Thread.isMainThread {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        } else {
            Task { @MainActor in
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
        }
    }
}
