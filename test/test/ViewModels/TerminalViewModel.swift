import Foundation
import SwiftUI

struct TerminalEntry: Identifiable, Equatable {
    enum Kind {
        case system
        case output
        case error
    }

    let id = UUID()
    let kind: Kind
    let text: String
}

@MainActor
final class TerminalViewModel: ObservableObject {
    @Published var entries: [TerminalEntry] = []
    @Published var input: String = ""
    @Published var isConnected = false
    @Published var isConnecting = false

    let server: ServerConfig

    private let session: TerminalSession
    private var sessionTask: Task<Void, Never>?
    private var history: [String] = []
    private var historyIndex: Int?

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

    func connectIfNeeded() {
        guard sessionTask == nil else { return }

        sessionTask = Task { [weak self] in
            guard let self else { return }
            await self.session.start { event in
                await self.handle(event)
            }
        }
    }

    func disconnect() {
        sessionTask?.cancel()
        sessionTask = nil

        Task {
            await session.stop()
        }

        isConnected = false
        isConnecting = false
    }

    func sendCurrentCommand() {
        let command = input
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if history.last != command {
            history.append(command)
        }
        historyIndex = nil
        input = ""

        Task {
            do {
                try await session.send(command + "\n")
            } catch {
                append(.error, "发送失败: \(describe(error))")
            }
        }
    }

    func sendInterrupt() {
        Task {
            do {
                try await session.send("\u{03}")
            } catch {
                append(.error, "中断失败: \(describe(error))")
            }
        }
    }

    func clearOutput() {
        entries.removeAll()
    }

    func moveHistoryBackward() {
        guard !history.isEmpty else { return }

        if let historyIndex {
            self.historyIndex = max(historyIndex - 1, 0)
        } else {
            historyIndex = history.count - 1
        }

        if let historyIndex {
            input = history[historyIndex]
        }
    }

    func moveHistoryForward() {
        guard !history.isEmpty, let historyIndex else { return }

        let nextIndex = historyIndex + 1
        if nextIndex < history.count {
            self.historyIndex = nextIndex
            input = history[nextIndex]
        } else {
            self.historyIndex = nil
            input = ""
        }
    }

    private func handle(_ event: TerminalSession.Event) async {
        switch event {
        case .connecting(let host):
            isConnecting = true
            isConnected = false
            append(.system, "Connecting to \(host)...")
        case .connected:
            isConnecting = false
            isConnected = true
            append(.system, "Connected. Interactive shell ready.")
        case .output(let text):
            append(.output, text)
        case .error(let message):
            isConnecting = false
            isConnected = false
            append(.error, message)
        case .disconnected:
            isConnecting = false
            if isConnected {
                append(.system, "Connection closed.")
            }
            isConnected = false
            sessionTask = nil
        }
    }

    private func append(_ kind: TerminalEntry.Kind, _ text: String) {
        guard !text.isEmpty else { return }
        entries.append(TerminalEntry(kind: kind, text: text))
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
