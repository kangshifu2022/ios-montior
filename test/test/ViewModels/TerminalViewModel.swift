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
    @Published private(set) var recoverableSessions: [TerminalSavedSession] = []
    @Published private(set) var latestSnapshot: TerminalSavedSession?

    let server: ServerConfig

    private let session: TerminalSession
    private var sessionTask: Task<Void, Never>?
    private var outputSink: (([UInt8]) -> Void)?
    private var pendingOutput: [[UInt8]] = []
    private var terminalSize = TerminalSize.fallback
    private var keepsSessionAlive = false
    private var exitRequestedByUser = false
    private var hasPreparedLaunch = false
    private var activeSessionRecord: TerminalSavedSession?
    private var scrollbackBuffer = Data()
    private var scrollbackFlushTask: Task<Void, Never>?

    private static let maxScrollbackBytes = 96 * 1024

    init(server: ServerConfig) {
        self.server = server
        self.session = TerminalSession(server: server)
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

    var hasSavedLaunchChoices: Bool {
        !recoverableSessions.isEmpty || latestSnapshot != nil
    }

    func prepareLaunchIfNeeded() {
        guard !hasPreparedLaunch else { return }
        hasPreparedLaunch = true
        refreshSessionSummaries()

        let restorePolicy = TerminalPersistenceStore.restorePolicy()
        let defaultMode = TerminalPersistenceStore.defaultConnectionMode()
        let shouldAsk = restorePolicy == .askEveryTime && hasSavedLaunchChoices

        if shouldAsk {
            isShowingLaunchSheet = true
            return
        }

        if restorePolicy == .resumeMostRecent, let mostRecent = recoverableSessions.first {
            resumePersistentSession(mostRecent)
            return
        }

        switch defaultMode {
        case .persistentTmux:
            startNewPersistentSession()
        case .directSSH:
            startDirectSession()
        }
    }

    func connectIfNeeded() {
        guard sessionTask == nil, let activeSessionRecord else { return }
        lastError = nil
        keepsSessionAlive = true
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
        activate(record)
    }

    func startNewPersistentSession() {
        let record = TerminalPersistenceStore.createPersistentSession(for: server)
        activate(record)
    }

    func resumePersistentSession(_ session: TerminalSavedSession) {
        let record = TerminalPersistenceStore.markAttached(session)
        activate(record)
    }

    func reconnect() {
        exitRequestedByUser = false
        disconnect(clearError: true)
        connectIfNeeded()
    }

    func disconnect(clearError: Bool = false) {
        keepsSessionAlive = false
        exitRequestedByUser = false
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
        flushPendingOutput()
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

    func sendExit() {
        keepsSessionAlive = false
        exitRequestedByUser = true
        send(text: "exit\n")
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
        lastError = nil
        terminalTitle = nil
        shouldDismissTerminal = false
        isShowingLaunchSheet = false
        pendingOutput.removeAll()
        activeSessionRecord = record
        scrollbackBuffer = record.scrollback
        scrollbackFlushTask?.cancel()
        scrollbackFlushTask = nil
        refreshSessionSummaries()
        connectIfNeeded()
    }

    private func handle(_ event: TerminalSession.Event) async {
        switch event {
        case .connecting:
            isConnecting = true
            isConnected = false
            lastError = nil
        case .connected:
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
            } else {
                pendingOutput.append(bytes)
            }
        case .error(let message):
            isConnecting = false
            isConnected = false
            lastError = message
        case .disconnected:
            flushScrollbackNowIfNeeded()
            isConnecting = false
            isConnected = false
            sessionTask = nil

            if exitRequestedByUser, let activeSessionRecord, activeSessionRecord.kind == .persistentTmux {
                self.activeSessionRecord = TerminalPersistenceStore.markEnded(activeSessionRecord.id) ?? activeSessionRecord
            }

            refreshSessionSummaries()

            if exitRequestedByUser {
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

    private func flushPendingOutput() {
        guard let outputSink, !pendingOutput.isEmpty else { return }
        pendingOutput.forEach(outputSink)
        pendingOutput.removeAll()
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
