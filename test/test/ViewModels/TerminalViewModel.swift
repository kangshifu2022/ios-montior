import Foundation
import Combine
import SwiftUI

enum TerminalConnectionStage: Int, CaseIterable, Sendable {
    case idle
    case preparing
    case establishingSSH
    case openingTerminal
    case waitingForInitialOutput
    case ready

    var title: String {
        switch self {
        case .idle:
            return "等待开始"
        case .preparing:
            return "准备连接"
        case .establishingSSH:
            return "建立 SSH 连接"
        case .openingTerminal:
            return "打开终端"
        case .waitingForInitialOutput:
            return "等待首屏输出"
        case .ready:
            return "连接完成"
        }
    }

    var detail: String {
        switch self {
        case .idle:
            return "尚未开始当前终端会话。"
        case .preparing:
            return "正在整理会话信息并准备发起连接。"
        case .establishingSSH:
            return "正在与远端服务器建立 SSH 会话。"
        case .openingTerminal:
            return "SSH 已连通，正在申请 PTY 并打开终端。"
        case .waitingForInitialOutput:
            return "终端已打开，正在等待远端返回首屏内容。"
        case .ready:
            return "远端终端已就绪。"
        }
    }
}

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var isConnected = false
    @Published var isConnecting = false
    @Published var terminalTitle: String?
    @Published var lastError: String?
    @Published var shouldDismissTerminal = false
    @Published var shouldSuspendTerminal = false
    @Published var isShowingLaunchSheet = false
    @Published var isShowingTmuxSessionPicker = false
    @Published private(set) var isAwaitingTerminalOutput = false
    @Published private(set) var connectionStage: TerminalConnectionStage = .idle
    @Published private(set) var connectionStageText: String?
    @Published private(set) var lastConnectionIssueText: String?
    @Published private(set) var keyboardFocusRequestID = 0
    @Published private(set) var recoverableSessions: [TerminalSavedSession] = []
    @Published private(set) var latestSnapshot: TerminalSavedSession?
    @Published private(set) var remoteTmuxSessions: [TerminalRemoteTmuxSession] = []
    @Published private(set) var isRefreshingRemoteTmuxSessions = false
    @Published private(set) var creatingRemoteTmuxSessionName: String?
    @Published private(set) var deletingRemoteTmuxSessionName: String?
    @Published private(set) var remoteTmuxStatusText: String?
    @Published private(set) var isRemoteTmuxAvailable = true

    let server: ServerConfig

    private let session: TerminalSession
    private var sessionTask: Task<Void, Never>?
    private var remoteTmuxFetchTask: Task<Void, Never>?
    private var remoteTmuxCreateTask: Task<Void, Never>?
    private var remoteTmuxDeleteTask: Task<Void, Never>?
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
    private var launchKickoffWatchdogTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var scrollbackReplayTask: Task<Void, Never>?
    private var activeConnectionAttemptID = 0
    private var isDisconnectingSession = false
    private var pendingConnectAfterDisconnect = false
    private var launchKickoffRecoveryCount = 0

    private static let maxScrollbackBytes = 96 * 1024
    private static let replayInspectionWindowBytes = 2048
    private static let replayChunkBytes = 4096
    private static let connectionStageTimeoutNanoseconds: UInt64 = 15_000_000_000
    private static let launchKickoffWatchdogNanoseconds: UInt64 = 1_500_000_000
    private static let maxLaunchKickoffRecoveries = 1

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

    var activePersistentSessionName: String? {
        guard activeSessionRecord?.kind == .persistentTmux else {
            return nil
        }
        return activeSessionRecord?.sessionName
    }

    var hasSessionToSuspend: Bool {
        activeSessionRecord != nil && (isConnected || isAwaitingTerminalOutput)
    }

    var isTerminalReadyForPresentation: Bool {
        activeSessionRecord != nil && isConnected && !isAwaitingTerminalOutput
    }

    var shouldReuseWorkspaceSession: Bool {
        guard activeSessionRecord != nil else { return false }
        return isConnected || isAwaitingTerminalOutput || (isConnecting && sessionTask != nil)
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
        guard !isDisconnectingSession else {
            pendingConnectAfterDisconnect = true
            TerminalDiagnosticsStore.record(
                "connect deferred while previous session teardown is still in progress",
                category: "connection",
                server: server,
                session: activeSessionRecord
            )
            return
        }
        guard sessionTask == nil, let activeSessionRecord else { return }
        lastError = nil
        lastConnectionIssueText = nil
        pendingConnectAfterDisconnect = false
        shouldDismissTerminal = false
        shouldSuspendTerminal = false
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
        scheduleLaunchKickoffWatchdog(for: attemptID)

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

    func createRemoteTmuxSession(named requestedSessionName: String) {
        let sessionName = requestedSessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionName.isEmpty, creatingRemoteTmuxSessionName == nil else { return }

        remoteTmuxFetchTask?.cancel()
        remoteTmuxFetchTask = nil
        isRefreshingRemoteTmuxSessions = false
        remoteTmuxCreateTask?.cancel()
        creatingRemoteTmuxSessionName = sessionName

        let server = self.server
        remoteTmuxCreateTask = Task {
            let result = await TerminalTmuxService.createSession(named: sessionName, config: server)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.creatingRemoteTmuxSessionName = nil
                self.remoteTmuxCreateTask = nil

                switch result {
                case .success(let createResult):
                    self.remoteTmuxStatusText = createResult.notice
                    switch createResult.status {
                    case .tmuxUnavailable:
                        self.isRemoteTmuxAvailable = false
                    case .created, .alreadyExists:
                        self.isRemoteTmuxAvailable = true
                    }

                    switch createResult.status {
                    case .created:
                        self.switchToRemoteTmuxSession(named: sessionName)
                    case .alreadyExists, .tmuxUnavailable:
                        break
                    }
                case .failure(let error):
                    self.remoteTmuxStatusText = error.message
                }
            }
        }
    }

    func deleteRemoteTmuxSession(named sessionName: String) {
        guard deletingRemoteTmuxSessionName == nil else { return }

        remoteTmuxDeleteTask?.cancel()
        deletingRemoteTmuxSessionName = sessionName

        let server = self.server
        remoteTmuxDeleteTask = Task {
            let result = await TerminalTmuxService.deleteSession(named: sessionName, config: server)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.deletingRemoteTmuxSessionName = nil
                self.remoteTmuxDeleteTask = nil

                switch result {
                case .success(let deleteResult):
                    self.remoteTmuxStatusText = deleteResult.notice
                    switch deleteResult.status {
                    case .tmuxUnavailable:
                        self.isRemoteTmuxAvailable = false
                    case .deleted, .alreadyMissing:
                        self.isRemoteTmuxAvailable = true
                    }
                    self.remoteTmuxSessions.removeAll { $0.name == sessionName }
                    TerminalPersistenceStore.removePersistentSession(
                        for: self.server.id,
                        sessionName: sessionName
                    )
                    if var activeSessionRecord = self.activeSessionRecord,
                       activeSessionRecord.kind == .persistentTmux,
                       activeSessionRecord.sessionName == sessionName {
                        activeSessionRecord.allowsResume = false
                        self.activeSessionRecord = activeSessionRecord
                    }
                    self.refreshSessionSummaries()
                    self.refreshRemoteTmuxSessions()
                case .failure(let error):
                    self.remoteTmuxStatusText = error.message
                }
            }
        }
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
                    self.isRemoteTmuxAvailable = snapshot.isTmuxAvailable
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
        launchKickoffRecoveryCount = 0
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
        remoteTmuxCreateTask?.cancel()
        remoteTmuxCreateTask = nil
        isRefreshingRemoteTmuxSessions = false
        creatingRemoteTmuxSessionName = nil
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        launchKickoffWatchdogTask?.cancel()
        launchKickoffWatchdogTask = nil
        connectionStageText = nil
        if clearError {
            connectionStage = .idle
        }
        isAwaitingTerminalOutput = false
        flushScrollbackNowIfNeeded()
        scrollbackFlushTask?.cancel()
        scrollbackFlushTask = nil
        sessionTask?.cancel()
        sessionTask = nil
        pendingConnectAfterDisconnect = false
        disconnectTask?.cancel()
        isDisconnectingSession = true

        disconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.session.stop()
            await MainActor.run {
                self.isDisconnectingSession = false
                self.disconnectTask = nil
                if self.pendingConnectAfterDisconnect {
                    self.pendingConnectAfterDisconnect = false
                    self.connectIfNeeded()
                }
            }
        }

        isConnected = false
        isConnecting = false
        if clearError {
            lastError = nil
            lastConnectionIssueText = nil
        }
    }

    func attachOutputSink(_ sink: @escaping ([UInt8]) -> Void) {
        scrollbackReplayTask?.cancel()
        outputSink = sink
        let replayBuffer = replayableScrollbackBuffer()
        if !replayBuffer.isEmpty {
            replayScrollback(replayBuffer, into: sink)
        }
    }

    func detachOutputSink() {
        scrollbackReplayTask?.cancel()
        scrollbackReplayTask = nil
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

    func suspendTerminal() {
        TerminalDiagnosticsStore.record(
            "suspend terminal requested",
            category: "connection",
            server: server,
            session: activeSessionRecord
        )
        shouldSuspendTerminal = true
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

    func acknowledgeSuspendRequest() {
        shouldSuspendTerminal = false
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
        connectionStage = .idle
        connectionStageText = nil
        terminalTitle = nil
        shouldDismissTerminal = false
        shouldSuspendTerminal = false
        isShowingLaunchSheet = false
        isShowingTmuxSessionPicker = false
        isConnected = false
        isConnecting = false
        isAwaitingTerminalOutput = false
        launchKickoffWatchdogTask?.cancel()
        launchKickoffWatchdogTask = nil
        launchKickoffRecoveryCount = 0
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
            launchKickoffWatchdogTask?.cancel()
            launchKickoffWatchdogTask = nil
            isConnecting = false
            isConnected = true
            isAwaitingTerminalOutput = false
            shouldDismissTerminal = false
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            connectionStage = .ready
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
            launchKickoffWatchdogTask?.cancel()
            launchKickoffWatchdogTask = nil
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
            launchKickoffWatchdogTask?.cancel()
            launchKickoffWatchdogTask = nil
            isConnecting = false
            isConnected = false
            isAwaitingTerminalOutput = false
            connectionTimeoutTask?.cancel()
            connectionTimeoutTask = nil
            connectionStageText = nil
            if lastConnectionIssueText == nil {
                connectionStage = .idle
            }
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

    private func replayScrollback(_ replayBuffer: [UInt8], into sink: @escaping ([UInt8]) -> Void) {
        guard !replayBuffer.isEmpty else { return }

        scrollbackReplayTask = Task { @MainActor [weak self] in
            var offset = 0

            while offset < replayBuffer.count {
                guard let self, !Task.isCancelled else { return }
                guard self.outputSink != nil else { return }

                let end = min(offset + Self.replayChunkBytes, replayBuffer.count)
                sink(Array(replayBuffer[offset..<end]))
                offset = end

                if offset < replayBuffer.count {
                    await Task.yield()
                }
            }

            self?.scrollbackReplayTask = nil
        }
    }

    private func updateConnectionStage(_ message: String) {
        connectionStage = Self.stage(for: message)
        connectionStageText = message
        if connectionStage != .preparing {
            launchKickoffWatchdogTask?.cancel()
            launchKickoffWatchdogTask = nil
            launchKickoffRecoveryCount = 0
        }
        scheduleConnectionTimeout(for: message)
    }

    private func scheduleLaunchKickoffWatchdog(for attemptID: Int) {
        launchKickoffWatchdogTask?.cancel()
        launchKickoffWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.launchKickoffWatchdogNanoseconds)
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self,
                      self.activeConnectionAttemptID == attemptID,
                      self.activeSessionRecord != nil,
                      self.isConnecting,
                      self.connectionStage == .preparing,
                      self.lastConnectionIssueText == nil else {
                    return
                }

                TerminalDiagnosticsStore.record(
                    "launch stalled before ssh stage, sessionTaskActive=\(self.sessionTask != nil), recoveryCount=\(self.launchKickoffRecoveryCount)",
                    level: .warning,
                    category: "connection",
                    server: self.server,
                    session: self.activeSessionRecord
                )

                self.launchKickoffWatchdogTask?.cancel()
                self.launchKickoffWatchdogTask = nil

                if self.launchKickoffRecoveryCount < Self.maxLaunchKickoffRecoveries {
                    self.launchKickoffRecoveryCount += 1
                    self.suppressNextDisconnectDismiss = true
                    self.disconnect(clearError: true)
                    self.connectIfNeeded()
                    return
                }

                let issue = "终端启动卡住：还没进入 SSH 连接阶段"
                self.lastConnectionIssueText = issue
                self.lastError = issue
                self.disconnect(clearError: false)
            }
        }
    }

    private static func stage(for message: String) -> TerminalConnectionStage {
        if message.contains("准备") {
            return .preparing
        }
        if message.contains("首屏输出") {
            return .waitingForInitialOutput
        }
        if message.contains("打开终端") {
            return .openingTerminal
        }
        if message.contains("建立 SSH") {
            return .establishingSSH
        }
        return .preparing
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
