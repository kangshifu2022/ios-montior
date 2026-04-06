import Foundation

enum TerminalPersistenceStore {
    private static let sessionsKey = "terminal.savedSessions.v1"
    private static let maxSessionsPerServer = 8

    static func defaultConnectionMode() -> TerminalDefaultConnectionMode {
        let rawValue = UserDefaults.standard.string(forKey: TerminalDefaultConnectionMode.storageKey)
        return TerminalDefaultConnectionMode(rawValue: rawValue ?? "") ?? .persistentTmux
    }

    static func restorePolicy() -> TerminalRestorePolicy {
        let rawValue = UserDefaults.standard.string(forKey: TerminalRestorePolicy.storageKey)
        return TerminalRestorePolicy(rawValue: rawValue ?? "") ?? .askEveryTime
    }

    static func recoverableSessions(for server: ServerConfig) -> [TerminalSavedSession] {
        loadSessions()
            .filter { $0.serverID == server.id && $0.isRecoverable }
            .sorted { $0.sortDate > $1.sortDate }
    }

    static func latestSnapshot(for server: ServerConfig) -> TerminalSavedSession? {
        loadSessions()
            .filter { $0.serverID == server.id && !$0.preview.isEmpty }
            .sorted { $0.sortDate > $1.sortDate }
            .first
    }

    static func beginDirectSession(for server: ServerConfig) -> TerminalSavedSession {
        let now = Date()
        let record = TerminalSavedSession(
            id: directRecordID(for: server.id),
            serverID: server.id,
            serverName: server.name,
            kind: .directSSH,
            sessionName: nil,
            title: "\(server.name) 直连",
            createdAt: now,
            lastAttachedAt: now,
            lastOutputAt: now,
            allowsResume: false,
            scrollback: Data(),
            preview: ""
        )

        return upsert(record)
    }

    static func createPersistentSession(for server: ServerConfig) -> TerminalSavedSession {
        createPersistentSession(for: server, preferredSessionName: nil)
    }

    static func createPersistentSession(for server: ServerConfig, preferredSessionName: String?) -> TerminalSavedSession {
        let now = Date()
        let trimmedSessionName = preferredSessionName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionName = {
            if let trimmedSessionName, !trimmedSessionName.isEmpty {
                return trimmedSessionName
            }
            return makeSessionName(for: server, at: now)
        }()
        let recordID = persistentRecordID(for: server.id, sessionName: sessionName)

        if let existing = updateRecord(id: recordID, mutate: { record in
            record.serverName = server.name
            record.sessionName = sessionName
            record.lastAttachedAt = now
            record.allowsResume = true
        }) {
            return existing
        }

        let record = TerminalSavedSession(
            id: recordID,
            serverID: server.id,
            serverName: server.name,
            kind: .persistentTmux,
            sessionName: sessionName,
            title: server.name,
            createdAt: now,
            lastAttachedAt: now,
            lastOutputAt: now,
            allowsResume: true,
            scrollback: Data(),
            preview: ""
        )

        return upsert(record)
    }

    static func markAttached(_ session: TerminalSavedSession) -> TerminalSavedSession {
        updateRecord(id: session.id) { record in
            record.serverName = session.serverName
            record.title = session.title
            record.lastAttachedAt = Date()
            if record.kind == .persistentTmux {
                record.allowsResume = true
            }
        } ?? session
    }

    static func updateTitle(_ title: String?, for recordID: String) -> TerminalSavedSession? {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return updateRecord(id: recordID) { record in
            record.title = title
        }
    }

    static func updateScrollback(_ scrollback: Data, for recordID: String, fallbackTitle: String?) -> TerminalSavedSession? {
        updateRecord(id: recordID) { record in
            record.scrollback = scrollback
            record.preview = makePreview(from: scrollback)
            record.lastOutputAt = Date()
            if let fallbackTitle, !fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                record.title = fallbackTitle
            }
        }
    }

    static func markEnded(_ recordID: String) -> TerminalSavedSession? {
        updateRecord(id: recordID) { record in
            record.allowsResume = false
        }
    }

    private static func upsert(_ record: TerminalSavedSession) -> TerminalSavedSession {
        var sessions = loadSessions()

        if let index = sessions.firstIndex(where: { $0.id == record.id }) {
            sessions[index] = record
        } else {
            sessions.append(record)
        }

        prunePersistentSessions(in: &sessions, for: record.serverID)
        saveSessions(sessions)
        return sessions.first(where: { $0.id == record.id }) ?? record
    }

    private static func updateRecord(id: String, mutate: (inout TerminalSavedSession) -> Void) -> TerminalSavedSession? {
        var sessions = loadSessions()
        guard let index = sessions.firstIndex(where: { $0.id == id }) else {
            return nil
        }

        mutate(&sessions[index])
        prunePersistentSessions(in: &sessions, for: sessions[index].serverID)
        saveSessions(sessions)
        return sessions[index]
    }

    private static func prunePersistentSessions(in sessions: inout [TerminalSavedSession], for serverID: UUID) {
        let directSessions = sessions.filter { !($0.serverID == serverID && $0.kind == .persistentTmux) }
        let persistentSessions = sessions
            .filter { $0.serverID == serverID && $0.kind == .persistentTmux }
            .sorted { $0.sortDate > $1.sortDate }
        let keptPersistent = Array(persistentSessions.prefix(maxSessionsPerServer))

        sessions = directSessions + keptPersistent
    }

    private static func loadSessions() -> [TerminalSavedSession] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([TerminalSavedSession].self, from: data) else {
            return []
        }

        return decoded
    }

    private static func saveSessions(_ sessions: [TerminalSavedSession]) {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        UserDefaults.standard.set(data, forKey: sessionsKey)
    }

    private static func directRecordID(for serverID: UUID) -> String {
        "direct:\(serverID.uuidString)"
    }

    private static func persistentRecordID(for serverID: UUID, sessionName: String) -> String {
        "tmux:\(serverID.uuidString):\(sessionName)"
    }

    private static func makeSessionName(for server: ServerConfig, at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        let preferredBase = server.name.isEmpty ? server.host : server.name
        let base = sanitize(preferredBase)
        return "ios-\(base)-\(formatter.string(from: date))"
    }

    private static func sanitize(_ value: String) -> String {
        let scalars = value.unicodeScalars.map { scalar -> String in
            if CharacterSet.alphanumerics.contains(scalar) {
                return String(scalar)
            }
            return "-"
        }

        let collapsed = scalars.joined()
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed.isEmpty ? "server" : collapsed.lowercased()
    }

    private static func makePreview(from scrollback: Data) -> String {
        guard !scrollback.isEmpty else { return "" }

        let recent = Data(scrollback.suffix(4096))
        var text = String(decoding: recent, as: UTF8.self)
        text = text.replacingOccurrences(
            of: #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\u{001B}[@-_]"#,
            with: "",
            options: .regularExpression
        )
        let filteredScalars = text.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\r" || scalar == "\t" || scalar.value >= 32
        }
        text = filteredScalars.map(String.init).joined()

        let lines = text
            .split(whereSeparator: \.isNewline)
            .suffix(5)
            .map(String.init)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
