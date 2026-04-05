import Foundation

extension Notification.Name {
    static let terminalDiagnosticsDidChange = Notification.Name("terminalDiagnosticsDidChange")
}

enum TerminalDiagnosticsStore {
    private static let storageKey = "terminal.diagnostics.entries.v1"
    private static let maxEntries = 300
    private static let queue = DispatchQueue(label: "terminal.diagnostics.store")

    static func record(
        _ message: String,
        level: TerminalDiagnosticLevel = .info,
        category: String,
        server: ServerConfig? = nil,
        session: TerminalSavedSession? = nil
    ) {
        let entry = TerminalDiagnosticEntry(
            level: level,
            category: category,
            serverName: server?.name ?? session?.serverName,
            serverHost: server?.host,
            sessionName: session?.sessionName,
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

    static func loadEntries() -> [TerminalDiagnosticEntry] {
        queue.sync {
            loadEntriesUnlocked().sorted { $0.timestamp > $1.timestamp }
        }
    }

    static func clear() {
        queue.sync {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        notifyDidChange()
    }

    static func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let entries = loadEntries().reversed()
        guard !entries.isEmpty else {
            return "还没有终端诊断日志。"
        }

        return entries.map { entry in
            var fragments: [String] = []
            fragments.append(formatter.string(from: entry.timestamp))
            fragments.append("[\(entry.level.title)]")
            fragments.append("[\(entry.category)]")

            if let serverSummary = entry.serverSummary, !serverSummary.isEmpty {
                fragments.append("[\(serverSummary)]")
            }

            if let sessionName = entry.sessionName, !sessionName.isEmpty {
                fragments.append("[session=\(sessionName)]")
            }

            fragments.append(entry.message)
            return fragments.joined(separator: " ")
        }
        .joined(separator: "\n")
    }

    private static func loadEntriesUnlocked() -> [TerminalDiagnosticEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([TerminalDiagnosticEntry].self, from: data) else {
            return []
        }

        return decoded
    }

    private static func saveEntriesUnlocked(_ entries: [TerminalDiagnosticEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func notifyDidChange() {
        let post = {
            NotificationCenter.default.post(name: .terminalDiagnosticsDidChange, object: nil)
        }

        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}
