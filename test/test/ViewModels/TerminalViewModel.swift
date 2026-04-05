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

    let server: ServerConfig

    private let session: TerminalSession
    private var sessionTask: Task<Void, Never>?
    private var outputSink: (([UInt8]) -> Void)?
    private var pendingOutput: [[UInt8]] = []
    private var terminalSize = TerminalSize.fallback
    private var suspendedForBackground = false
    private var exitRequestedByUser = false

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
        return server.name
    }

    func connectIfNeeded() {
        guard sessionTask == nil else { return }
        lastError = nil

        sessionTask = Task { [weak self] in
            guard let self else { return }
            await self.session.start(terminalSize: self.terminalSize) { event in
                await self.handle(event)
            }
        }
    }

    func reconnect() {
        exitRequestedByUser = false
        suspendedForBackground = false
        disconnect(clearError: true)
        connectIfNeeded()
    }

    func disconnect(clearError: Bool = false) {
        exitRequestedByUser = false
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

    func sendPipe() {
        send(text: "|")
    }

    func sendExit() {
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
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            guard suspendedForBackground else { return }
            suspendedForBackground = false
            connectIfNeeded()
        case .background:
            guard sessionTask != nil else { return }
            suspendedForBackground = true
            disconnect(clearError: true)
        case .inactive:
            break
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
            if let outputSink {
                outputSink(bytes)
            } else {
                pendingOutput.append(bytes)
            }
        case .error(let message):
            isConnecting = false
            isConnected = false
            lastError = message
            suspendedForBackground = false
        case .disconnected:
            isConnecting = false
            isConnected = false
            sessionTask = nil
            if exitRequestedByUser {
                shouldDismissTerminal = true
            }
            exitRequestedByUser = false
        }
    }

    private func flushPendingOutput() {
        guard let outputSink, !pendingOutput.isEmpty else { return }
        pendingOutput.forEach(outputSink)
        pendingOutput.removeAll()
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
}
