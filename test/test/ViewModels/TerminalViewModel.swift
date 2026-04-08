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
    @Published var isShowingTmuxSessionPicker = false
    @Published private(set) var isAwaitingTerminalOutput = false
    @Published private(set) var connectionStageText: String?
    @Published private(set) var lastConnectionIssueText: String?
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
    private var bootstrapCommandOverride: BootstrapCommandOverride?
    private var keepsSessionAlive = false
    private var exitRequestedByUser = false
    private var suppressNextDisconnectDismiss = false
    private var hasPreparedLaunch = false
    private var activeSessionRecord: TerminalSavedSession?
    private var scrollbackBuffer = Data()
    private var scrollbackFlushTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var activeConnectionAttemptID = 0

    private static let maxScrollbackBytes = 96 * 1024
    private static let replayInspectionWindowBytes = 2048
    private static let connectionStageTimeoutNanoseconds: UInt64 = 15_000_000_000

    private struct BootstrapCommandOverride {
        let recordID: String
        let command: String
    }

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
        if isAwaitingTerminalOutput {
            return "等待响应"
        }
        if lastConnectionIssueText != nil {
            return "连接失败"
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

        if let connectionNoticeText {
            switch activeSessionRecord.kind {
            case .persistentTmux:
                if let sessionName = activeSessionRecord.sessionName, !sessionName.isEmpty {
                    return "tmux · \(sessionName) · \(connectionNoticeText)"
                }
                return "tmux · \(connectionNoticeText)"
            case .directSSH:
                return "SSH · \(connectionNoticeText)"
            }
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

    var connectionNoticeText: String? {
        if showsConnectionProgressNotice {
            if let connectionStageText, !connectionStageText.isEmpty {
                return connectionStageText
            }

            if isAwaitingTerminalOutput {
                return "终端已打开，正在等待远端首屏输出…"
            }

            return "正在建立 SSH 连接…"
        }

        return lastConnectionIssueText
    }

    var showsConnectionProgressNotice: Bool {
        isConnecting || isAwaitingTerminalOutput
    }

    var showsConnectionFailureNotice: Bool {
        !showsConnectionProgressNotice && lastConnectionIssueText != nil
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
        lastConnectionIssueText = nil
        shouldDismissTerminal = false
        keepsSessionAlive = true
        isConnected = false
        isConnecting = true
        isAwaitingTerminalOutput = false
        updateConnectionStage("准备建立 SSH 连接…")
        TerminalDiagnosticsStore.record(
            "connect requested",
            category: "connection",
            server: server,
            session: activeSessionRecord
        )
        let bootstrapCommand = self.connectBootstrapCommand(for: activeSessionRecord)
        activeConnectionAttemptID &+= 1
        let attemptID = activeConnectionAttemptID

        sessionTask = Task { [weak self] in
            guard let self else { return }
            await self.session.start(
                terminalSize: self.terminalSize,
                bootstrapCommand: bootstrapCommand
            ) { event in
                await self.handle(event, attemptID: attemptID)
            }
        }
    }

    func startDirectSession() {
        bootstrapCommandOverride = nil
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
        bootstrapCommandOverride = nil
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
        bootstrapCommandOverride = nil
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
        bootstrapCommandOverride = nil
        let record = TerminalPersistenceStore.markAttached(session)
        TerminalDiagnosticsStore.record(
            "resume persistent session from saved state",
            category: "launch",
            server: server,
            session: record
        )
        activate(record)
    }

    func presentTmuxSessionPicker() {
        TerminalDiagnosticsStore.record(
            "present tmux session picker",
            category: "tmux-probe",
            server: server,
            session: activeSessionRecord
        )
        isShowingTmuxSessionPicker = true
    }

    func switchToRemoteTmuxSession(named sessionName: String) {
        let record = TerminalPersistenceStore.createPersistentSession(
            for: server,
            preferredSessionName: sessionName
        )
        bootstrapCommandOverride = BootstrapCommandOverride(
            recordID: record.id,
            command: Self.attachExistingTmuxBootstrapCommand(for: sessionName)
        )
        TerminalDiagnosticsStore.record(
            "switch to remote tmux session \(sessionName)",
            category: "launch",
            server: server,
            session: record
        )
        isShowingTmuxSessionPicker = false
        suppressNextDisconnectDismiss = true
        disconnect(clearError: true)
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
        suppressNextDisconnectDismiss = true
        disconnect(clearError: true)
        connectIfNeeded()
    }

    func restoreTerminalKeyboardFocus() {
        requestKeyboardFocus()
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
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        connectionStageText = nil
        isAwaitingTerminalOutput = false
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
            lastConnectionIssueText = nil
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
        lastConnectionIssueText = nil
        connectionStageText = nil
        terminalTitle = nil
        shouldDismissTerminal = false
        isShowingLaunchSheet = false
        isShowingTmuxSessionPicker = false
        isConnected = false
        isConnecting = false
        isAwaitingTerminalOutput = false
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

    private func handle(_ event: TerminalSession.Event, attemptID: Int) async {
        guard attemptID == activeConnectionAttemptID else {
            if case .output = event {
                return
            }

            TerminalDiagnosticsStore.record(
                "ignored stale event: \(Self.eventSummary(for: event))",
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            return
        }

        switch event {
        case .connecting(let message):
            TerminalDiagnosticsStore.record(
                "event connecting: \(message)",
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            isConnecting = true
            isConnected = false
            isAwaitingTerminalOutput = false
            lastError = nil
            lastConnectionIssueText = nil
            updateConnectionStage(message)
        case .awaitingInitialOutput(let message):
            TerminalDiagnosticsStore.record(
                "event awaiting initial output: \(message)",
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            isConnecting = false
            isConnected = true
            isAwaitingTerminalOutput = true
            lastError = nil
            lastConnectionIssueText = nil
            shouldDismissTerminal = false
            updateConnectionStage(message)
        case .connected:
            TerminalDiagnosticsStore.record(
                "event connected (initial output received)",
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            isConnecting = false
            isConnected = true
            isAwaitingTerminalOutput = false
            shouldDismissTerminal = false
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            connectionStageText = nil
            lastConnectionIssueText = nil
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
            isAwaitingTerminalOutput = false
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            connectionStageText = nil
            lastConnectionIssueText = message
            lastError = message
        case .disconnected:
            let endedGracefully = lastConnectionIssueText == nil && lastError == nil
            let shouldDismissAfterDisconnect = !suppressNextDisconnectDismiss && (exitRequestedByUser || endedGracefully)
            TerminalDiagnosticsStore.record(
                "event disconnected, exitRequested=\(exitRequestedByUser), graceful=\(endedGracefully), suppressDismiss=\(suppressNextDisconnectDismiss)",
                level: shouldDismissAfterDisconnect || suppressNextDisconnectDismiss ? .info : .warning,
                category: "event",
                server: server,
                session: activeSessionRecord
            )
            flushScrollbackNowIfNeeded()
            isConnecting = false
            isConnected = false
            isAwaitingTerminalOutput = false
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            connectionStageText = nil
            sessionTask = nil

            refreshSessionSummaries()

            if shouldDismissAfterDisconnect {
                shouldDismissTerminal = true
            }
            suppressNextDisconnectDismiss = false
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

    private func updateConnectionStage(_ message: String) {
        connectionStageText = message
        scheduleConnectionTimeout(for: message)
    }

    private func scheduleConnectionTimeout(for message: String) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.connectionStageTimeoutNanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.showsConnectionProgressNotice,
                      self.connectionStageText == message else {
                    return
                }

                let timeoutMessage = "连接超时：\(message)"
                TerminalDiagnosticsStore.record(
                    "connection timeout at stage \(message)",
                    level: .warning,
                    category: "connection",
                    server: self.server,
                    session: self.activeSessionRecord
                )
                self.connectionStageText = nil
                self.lastConnectionIssueText = timeoutMessage
                self.lastError = timeoutMessage
                self.disconnect(clearError: false)
            }
        }
    }

    private func connectBootstrapCommand(for record: TerminalSavedSession) -> String? {
        if let bootstrapCommandOverride,
           bootstrapCommandOverride.recordID == record.id {
            return bootstrapCommandOverride.command
        }

        return bootstrapCommand(for: record)
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

    private static func eventSummary(for event: TerminalSession.Event) -> String {
        switch event {
        case .connecting(let message):
            return "connecting(\(message))"
        case .awaitingInitialOutput(let message):
            return "awaitingInitialOutput(\(message))"
        case .connected:
            return "connected"
        case .output:
            return "output"
        case .error(let message):
            return "error(\(message))"
        case .disconnected:
            return "disconnected"
        }
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

    private static func attachExistingTmuxBootstrapCommand(for sessionName: String) -> String {
        let quotedSessionName = Self.singleQuoted(sessionName)
        return """
        if command -v tmux >/dev/null 2>&1; then
          if tmux has-session -t \(quotedSessionName) 2>/dev/null; then
            exec tmux attach-session -t \(quotedSessionName)
          else
            printf '\\r\\n[iOS Monitor] The selected tmux session is no longer available on this server. Continuing with a normal shell.\\r\\n'
          fi
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
