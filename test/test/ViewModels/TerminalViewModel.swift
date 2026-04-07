import Foundation
import Combine
import SwiftUI

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var terminalTitle: String?
    @Published var lastError: String?
    @Published var shouldDismissTerminal = false
    @Published var isShowingLaunchSheet = false
    @Published private(set) var keyboardFocusRequestID = 0
    @Published private(set) var recoverableSessions: [TerminalSavedSession] = []
    @Published private(set) var latestSnapshot: TerminalSavedSession?
    @Published private(set) var remoteTmuxSessions: [TerminalRemoteTmuxSession] = []
    @Published private(set) var isRefreshingRemoteTmuxSessions = false
    @Published private(set) var remoteTmuxStatusText: String?

    let server: ServerConfig

    private let session: TerminalSession
    private var sessionTask: Task<Void, Never>?
    private var remoteTmuxFetchTask: Task<Void, Never>?
    private var outputSink: (([UInt8]) -> Void)?
    private var terminalSize = TerminalSize.fallback
    private var keepsSessionAlive = false
    private var exitRequestedByUser = false
    private var hasPreparedLaunch = false
    private var activeSessionRecord: TerminalSavedSession?
    private var scrollbackBuffer = Data()
    private var scrollbackFlushTask: Task<Void, Never>?

    private static let maxScrollbackBytes = 96 * 1024
    private static let replayInspectionWindowBytes = 2048

    init(server: ServerConfig) {
        self.server = server
        self.session = TerminalSession(server: server)
        TerminalDiagnosticsStore.record(
            "view model initialized",
            category: "view-model",
            server: server
        )
    }

    var statusText: String {
        if isConnecting {
            return "连接中"
        }
        return isConnected ? "已连接" : "未连接"
    }

    var displayTitle: String {
        if let terminalTitle, !terminalTitle.isEmpty {
            return terminalTitle
        }
        if let sessionTitle = activeSessionRecord?.title, !sessionTitle.isEmpty {
            return sessionTitle
        }
        return server.name
    }

    var sessionSummaryText: String {
        guard let activeSessionRecord else {
            return statusText
        }

        switch activeSessionRecord.kind {
        case .persistentTmux:
            if let sessionName = activeSessionRecord.sessionName, !sessionName.isEmpty {
                return "tmux · \(sessionName) · \(statusText)"
            }
            return "tmux · \(statusText)"
        case .directSSH:
            return "SSH · \(statusText)"
        }
    }

    var isPersistentSession: Bool {
        activeSessionRecord?.kind == .persistentTmux
    }

    var hasSessionToSuspend: Bool {
        activeSessionRecord != nil
    }

    func prepareLaunchIfNeeded() {
        guard !hasPreparedLaunch else { return }
        hasPreparedLaunch = true
        refreshSessionSummaries()

        let restorePolicy = TerminalPersistenceStore.restorePolicy()
        let defaultMode = TerminalPersistenceStore.defaultConnectionMode()
        let shouldAsk = restorePolicy == .askEveryTime
        TerminalDiagnosticsStore.record(
            "prepare launch, restorePolicy=\(restorePolicy.rawValue), defaultMode=\(defaultMode.rawValue), recoverable=\(recoverableSessions.count)",
            category: "launch",
            server: server
        )

        if shouldAsk {
            isShowingLaunchSheet = true
            return
        }

        if restorePolicy == .resumeMostRecent, let mostRecent = recoverableSessions.first {
            resumePersistentSession(mostRecent)
            return
        }

        startDefaultConnection(using: defaultMode)
    }

    func connectIfNeeded() {
        guard sessionTask == nil, let activeSessionRecord else { return }
        lastError = nil
        keepsSessionAlive = true
        TerminalDiagnosticsStore.record(
            "connect requested",
            category: "connection",
            server: server,
            session: activeSessionRecord
        )
        let bootstrapCommand = self.bootstrapCommand(for: activeSessionRecord)

        sessionTask = Task { [weak self] in
            guard let self else { return }
            await self.session.start(
                terminalSize: self.terminalSize,
                bootstrapCommand: bootstrapCommand
            ) { event in
                await self.handle(event)
            }
        }
    }

    func startDirectSession() {
        let record = TerminalPersistenceStore.beginDirectSession(for: server)
        TerminalDiagnosticsStore.record(
            "start direct ssh session",
            category: "launch",
            server: server,
            session: record
        )
        activate(record)
    }

    func startNewPersistentSession() {
        let record = TerminalPersistenceStore.createPersistentSession(for: server)
        TerminalDiagnosticsStore.record(
            "start new persistent tmux session",
            category: "launch",
            server: server,
            session: record
        )
        activate(record)
    }

    func startPersistentSession(named requestedSessionName: String?) {
        let record = TerminalPersistenceStore.createPersistentSession(
            for: server,
            preferredSessionName: requestedSessionName
        )
        TerminalDiagnosticsStore.record(
            "start or attach named persistent session",
            category: "launch",
            server: server,
            session: record
        )
        activate(record)
    }

    func resumePersistentSession(_ session: TerminalSavedSession) {
        let record = TerminalPersistenceStore.markAttached(session)
        TerminalDiagnosticsStore.record(
            "resume persistent session from saved state",
            category: "launch",
            server: server,
            session: record
        )
        activate(record)
    }

    func refreshRemoteTmuxSessionsIfNeeded() {
        guard remoteTmuxSessions.isEmpty,
              remoteTmuxStatusText == nil,
              !isRefreshingRemoteTmuxSessions else {
            return
        }

        refreshRemoteTmuxSessions()
    }

    func refreshRemoteTmuxSessions() {
        remoteTmuxFetchTask?.cancel()
        isRefreshingRemoteTmuxSessions = true
        if remoteTmuxSessions.isEmpty {
            remoteTmuxStatusText = nil
        }

        let server = self.server
        remoteTmuxFetchTask = Task {
            let result = await TerminalTmuxService.fetchSessions(config: server)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                switch result {
                case .success(let snapshot):
                    self.remoteTmuxSessions = snapshot.sessions
                    self.remoteTmuxStatusText = snapshot.notice
                case .failure(let error):
                    self.remoteTmuxStatusText = error.message
                }
                self.isRefreshingRemoteTmuxSessions = false
                self.remoteTmuxFetchTask = nil
            }
        }
    }

    func reconnect() {
        TerminalDiagnosticsStore.record(
            "manual reconnect requested",
            category: "connection",
            server: server,
            session: activeSessionRecord
        )
        exitRequestedByUser = false
        disconnect(clearError: true)
        connectIfNeeded()
    }

    func disconnect(clearError: Bool = false) {
        TerminalDiagnosticsStore.record(
            "disconnect requested, clearError=\(clearError)",
            category: "connection",
            server: server,
            session: activeSessionRecord
        )
        keepsSessionAlive = false
        exitRequestedByUser = false
        remoteTmuxFetchTask?.cancel()
        remoteTmuxFetchTask = nil
        isRefreshingRemoteTmuxSessions = false
        flushScrollbackNowIfNeeded()
        scrollbackFlushTask?.cancel()
        scrollbackFlushTask = nil
        sessionTask?.cancel()
        sessionTask = nil

        Task {
            await session.stop()
        }

        isConnected = false
        isConnecting = false
        if clearError {
            lastError = nil
        }
    }

    func attachOutputSink(_ sink: @escaping ([UInt8]) -> Void) {
        outputSink = sink
        let replayBuffer = replayableScrollbackBuffer()
        if !replayBuffer.isEmpty {
            sink(replayBuffer)
        }
    }

    func detachOutputSink() {
        outputSink = nil
    }

    func send(text: String) {
        send(bytes: Array(text.utf8))
    }

    func send(bytes: [UInt8]) {
        Task {
            do {
                try await session.send(bytes)
            } catch {
                await MainActor.run {
                    self.lastError = self.describe(error)
                    TerminalDiagnosticsStore.record(
                        "send failed: \(self.describe(error))",
                        level: .warning,
                        category: "io",
                        server: self.server,
                        session: self.activeSessionRecord
                    )
                }
            }
        }
    }

    func sendInterrupt() {
        send(bytes: [3])
    }

    func sendEscape() {
        send(bytes: [27])
    }

    func sendTab() {
        send(bytes: [9])
    }

    func sendSlash() {
        send(text: "/")
    }

    func sendDash() {
        send(text: "-")
    }

    func sendPipe() {
        send(text: "|")
    }

    func sendTmuxList() {
        send(text: "tmux ls\n")
    }

    func closeTerminal() {
        TerminalDiagnosticsStore.record(
            "close terminal requested",
            category: "connection",
            server: server,
            session: activeSessionRecord
        )
        disconnect(clearError: true)
        shouldDismissTerminal = true
    }

    func sendHome() {
        send(bytes: [27, 91, 72])
    }

    func sendEnd() {
        send(bytes: [27, 91, 70])
    }

    func sendArrowUp() {
        send(bytes: [27, 91, 65])
    }

    func sendArrowDown() {
        send(bytes: [27, 91, 66])
    }

    func sendArrowRight() {
        send(bytes: [27, 91, 67])
    }

    func sendArrowLeft() {
        send(bytes: [27, 91, 68])
    }

    func sendClearScreen() {
        send(bytes: [12])
    }

    func clearError() {
        lastError = nil
    }

    func acknowledgeDismissRequest() {
        shouldDismissTerminal = false
    }

    func updateTerminalTitle(_ title: String?) {
        terminalTitle = title

        guard let activeSessionRecord,
              let updatedRecord = TerminalPersistenceStore.updateTitle(title, for: activeSessionRecord.id) else {
            return
        }

        self.activeSessionRecord = updatedRecord
        refreshSessionSummaries()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        TerminalDiagnosticsStore.record(
            "scene phase changed to \(phase.logLabel)",
            category: "scene",
            server: server,
            session: activeSessionRecord
        )
        switch phase {
        case .active:
            guard keepsSessionAlive, sessionTask == nil, activeSessionRecord != nil else { return }
            connectIfNeeded()
        case .background, .inactive:
            flushScrollbackNowIfNeeded()
        @unknown default:
            break
        }
    }

    func updateTerminalSize(columns: Int, rows: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        let newSize = TerminalSize(
            columns: columns,
            rows: rows,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )

        guard newSize != terminalSize else { return }
        terminalSize = newSize

        guard isConnected else { return }

        Task {
            try? await session.resize(to: newSize)
        }
    }

    private func activate(_ record: TerminalSavedSession) {
        remoteTmuxFetchTask?.cancel()
        remoteTmuxFetchTask = nil
        isRefreshingRemoteTmuxSessions = false
        lastError = nil
        terminalTitle = nil
        shouldDismissTerminal = false
        isShowingLaunchSheet = false
        activeSessionRecord = record
        scrollbackBuffer = record.scrollback
        scrollbackFlushTask?.cancel()
        scrollbackFlushTask = nil
        refreshSessionSummaries()
        TerminalDiagnosticsStore.record(
            "activate session",
            category: "launch",
            server: server,
            session: record
        )
        requestKeyboardFocus()
        connectIfNeeded()
    }

    private func handle(_ event: TerminalSession.Event) async {
        switch event {
        case .connecting:
            TerminalDiagnosticsStore.record(
                "event connecting",
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            isConnecting = true
            isConnected = false
            lastError = nil
        case .connected:
            TerminalDiagnosticsStore.record(
                "event connected",
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            isConnecting = false
            isConnected = true
            shouldDismissTerminal = false
            Task {
                try? await session.resize(to: terminalSize)
            }
        case .output(let bytes):
            appendToScrollback(bytes)
            if let outputSink {
                outputSink(bytes)
            }
        case .error(let message):
            TerminalDiagnosticsStore.record(
                "event error: \(message)",
                level: .error,
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            isConnecting = false
            isConnected = false
            lastError = message
        case .disconnected:
            let endedGracefully = lastError == nil
            TerminalDiagnosticsStore.record(
                "event disconnected, exitRequested=\(exitRequestedByUser), graceful=\(endedGracefully)",
                level: exitRequestedByUser || endedGracefully ? .info : .warning,
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            flushScrollbackNowIfNeeded()
            isConnecting = false
            isConnected = false
            sessionTask = nil

            refreshSessionSummaries()

            if exitRequestedByUser || endedGracefully {
                shouldDismissTerminal = true
            }
            exitRequestedByUser = false
        }
    }

    private func appendToScrollback(_ bytes: [UInt8]) {
        guard activeSessionRecord != nil else { return }

        scrollbackBuffer.append(contentsOf: bytes)
        if scrollbackBuffer.count > Self.maxScrollbackBytes {
            scrollbackBuffer = Data(scrollbackBuffer.suffix(Self.maxScrollbackBytes))
        }

        scheduleScrollbackFlush()
    }

    private func scheduleScrollbackFlush() {
        guard activeSessionRecord != nil else { return }

        scrollbackFlushTask?.cancel()
        scrollbackFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.flushScrollbackNowIfNeeded()
            }
        }
    }

    private func flushScrollbackNowIfNeeded() {
        scrollbackFlushTask?.cancel()
        scrollbackFlushTask = nil

        guard let activeSessionRecord,
              let updatedRecord = TerminalPersistenceStore.updateScrollback(
                scrollbackBuffer,
                for: activeSessionRecord.id,
                fallbackTitle: terminalTitle ?? activeSessionRecord.title
              ) else {
            return
        }

        self.activeSessionRecord = updatedRecord
        refreshSessionSummaries()
    }

    private func refreshSessionSummaries() {
        recoverableSessions = TerminalPersistenceStore.recoverableSessions(for: server)
        latestSnapshot = TerminalPersistenceStore.latestSnapshot(for: server)
    }

    private func startDefaultConnection(using mode: TerminalDefaultConnectionMode) {
        TerminalDiagnosticsStore.record(
            "start default connection using \(mode.rawValue)",
            category: "launch",
            server: server
        )
        switch mode {
        case .persistentTmux:
            startNewPersistentSession()
        case .directSSH:
            startDirectSession()
        }
    }

    private func requestKeyboardFocus() {
        keyboardFocusRequestID &+= 1
    }

    private func replayableScrollbackBuffer() -> [UInt8] {
        guard !scrollbackBuffer.isEmpty else { return [] }

        var replayData = scrollbackBuffer
        let wasTrimmedToLimit = replayData.count >= Self.maxScrollbackBytes

        if wasTrimmedToLimit {
            replayData = Self.dropPotentiallyCorruptedReplayPrefix(in: replayData)
        }

        // Normalize invalid UTF-8 boundaries introduced by byte trimming while preserving ANSI escapes.
        replayData = Data(String(decoding: replayData, as: UTF8.self).utf8)
        return Array(replayData)
    }

    private static func dropPotentiallyCorruptedReplayPrefix(in data: Data) -> Data {
        guard !data.isEmpty else { return data }

        let inspectionCount = min(data.count, replayInspectionWindowBytes)
        let inspectionPrefix = data.prefix(inspectionCount)

        if let lineBreakIndex = inspectionPrefix.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let nextIndex = data.index(after: lineBreakIndex)
            return Data(data.suffix(from: nextIndex))
        }

        if let escapeIndex = inspectionPrefix.firstIndex(of: 0x1B) {
            return Data(data.suffix(from: escapeIndex))
        }

        return data
    }

    private func bootstrapCommand(for record: TerminalSavedSession) -> String? {
        guard record.kind == .persistentTmux,
              let sessionName = record.sessionName,
              !sessionName.isEmpty else {
            return nil
        }

        let quotedSessionName = Self.singleQuoted(sessionName)
        return """
        if command -v tmux >/dev/null 2>&1; then
          exec tmux new-session -A -s \(quotedSessionName)
        else
          printf '\\r\\n[iOS Monitor] tmux is not installed on this server. Continuing with a normal shell.\\r\\n'
        fi

        """
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? TerminalSessionError {
            switch error {
            case .notReady:
                return "终端尚未就绪"
            }
        }
        return String(describing: error)
    }

    private static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

private extension ScenePhase {
    var logLabel: String {
        switch self {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }
}
