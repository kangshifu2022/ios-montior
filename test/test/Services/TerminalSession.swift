import Foundation
import Citadel
import NIOCore
import NIOSSH

actor TerminalSession {
    private static let sshHandshakePauseNanoseconds: UInt64 = 2_000_000_000

    enum Event: Sendable {
        case connecting(String)
        case awaitingInitialOutput(String)
        case connected
        case output([UInt8])
        case error(String)
        case disconnected
    }

    private let server: ServerConfig
    private var stdinWriter: (@Sendable ([UInt8]) async throws -> Void)?
    private var resizePTY: (@Sendable (TerminalSize) async throws -> Void)?
    private var closeConnection: (@Sendable () async -> Void)?
    private var activeRunID: UInt64 = 0
    private var stoppingRunIDs = Set<UInt64>()

    init(server: ServerConfig) {
        self.server = server
    }

    func start(
        terminalSize: TerminalSize,
        bootstrapCommand: String? = nil,
        onEvent: @escaping @Sendable (Event) async -> Void
    ) async {
        activeRunID &+= 1
        let runID = activeRunID
        stoppingRunIDs.remove(runID)
        let hasBootstrapCommand = !(bootstrapCommand ?? "").isEmpty
        TerminalDiagnosticsStore.record(
            "start requested with size \(terminalSize.columns)x\(terminalSize.rows), bootstrap=\(hasBootstrapCommand)",
            category: "session",
            server: server
        )
        TerminalDiagnosticsStore.record(
            "starting ssh connection to \(server.host):\(server.port)",
            category: "session",
            server: server
        )
        await onEvent(.connecting("正在建立 SSH 连接…"))

        let algorithms = SSHAlgorithms.all

        do {
            let client = try await SSHClient.connect(
                host: server.host,
                port: server.port,
                authenticationMethod: .passwordBased(
                    username: server.username,
                    password: server.password
                ),
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: algorithms,
                protocolOptions: [
                    .maximumPacketSize(1 << 20)
                ]
            )

            TerminalDiagnosticsStore.record(
                "ssh connection established",
                category: "session",
                server: server
            )
            await onEvent(.connecting("SSH 已连接，正在打开终端…"))
            let handshakePauseStartedAt = Date()
            TerminalDiagnosticsStore.record(
                "holding 2.0s after ssh handshake success before opening pty",
                category: "session",
                server: server
            )
            try await Task.sleep(nanoseconds: Self.sshHandshakePauseNanoseconds)
            TerminalDiagnosticsStore.record(
                String(format: "requesting pty channel after %.2fs handshake pause", Date().timeIntervalSince(handshakePauseStartedAt)),
                category: "session",
                server: server
            )

            setCloseConnection({
                try? await client.close()
            }, for: runID)

            try await client.withPTY(
                SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm",
                    terminalCharacterWidth: terminalSize.columns,
                    terminalRowHeight: terminalSize.rows,
                    terminalPixelWidth: terminalSize.pixelWidth,
                    terminalPixelHeight: terminalSize.pixelHeight,
                    terminalModes: .init([.ECHO: 1])
                )
            ) { ttyOutput, ttyStdinWriter in
                self.setStdinWriter(for: runID) { input in
                    try await ttyStdinWriter.write(ByteBuffer(bytes: input))
                }
                self.setPTYResizer(for: runID) { size in
                    try await ttyStdinWriter.changeSize(
                        cols: size.columns,
                        rows: size.rows,
                        pixelWidth: size.pixelWidth,
                        pixelHeight: size.pixelHeight
                    )
                }

                TerminalDiagnosticsStore.record(
                    "pty channel opened",
                    category: "session",
                    server: self.server
                )
                TerminalDiagnosticsStore.record(
                    "waiting for initial terminal output",
                    category: "session",
                    server: self.server
                )
                await onEvent(.awaitingInitialOutput("终端已打开，等待远端首屏输出…"))

                if let bootstrapCommand, !bootstrapCommand.isEmpty {
                    TerminalDiagnosticsStore.record(
                        "sending bootstrap command",
                        category: "session",
                        server: self.server
                    )
                    try await ttyStdinWriter.write(ByteBuffer(bytes: Array(bootstrapCommand.utf8)))
                }

                var hasDeliveredInitialOutput = false
                for try await event in ttyOutput {
                    let bytes: [UInt8]
                    switch event {
                    case .stdout(let buffer), .stderr(let buffer):
                        bytes = Array(buffer.readableBytesView)
                    }
                    guard !bytes.isEmpty else { continue }
                    if !hasDeliveredInitialOutput {
                        hasDeliveredInitialOutput = true
                        TerminalDiagnosticsStore.record(
                            "received initial terminal output",
                            category: "session",
                            server: self.server
                        )
                        await onEvent(.connected)
                    }
                    await onEvent(.output(bytes))
                }

                TerminalDiagnosticsStore.record(
                    "pty output stream finished",
                    category: "session",
                    server: self.server
                )
            }
        } catch is CancellationError {
            TerminalDiagnosticsStore.record(
                "session cancelled",
                category: "session",
                server: server
            )
            await onEvent(.disconnected)
        } catch {
            let wasStopping = stoppingRunIDs.contains(runID)
            if !wasStopping, !Self.isBenignClosure(error) {
                TerminalDiagnosticsStore.record(
                    "session error: \(Self.describe(error))",
                    level: .error,
                    category: "session",
                    server: server
                )
                await onEvent(.error(Self.describe(error)))
            }
            TerminalDiagnosticsStore.record(
                "session disconnected after error path",
                level: Self.isBenignClosure(error) ? .info : .warning,
                category: "session",
                server: server
            )
            await onEvent(.disconnected)
        }

        clearState(for: runID)
    }

    func send(_ input: [UInt8]) async throws {
        guard let stdinWriter else {
            throw TerminalSessionError.notReady
        }
        try await stdinWriter(input)
    }

    func resize(to terminalSize: TerminalSize) async throws {
        guard let resizePTY else {
            throw TerminalSessionError.notReady
        }
        try await resizePTY(terminalSize)
    }

    func stop() async {
        let runID = activeRunID
        stoppingRunIDs.insert(runID)
        TerminalDiagnosticsStore.record(
            "stop requested",
            category: "session",
            server: server
        )
        if activeRunID == runID {
            stdinWriter = nil
            resizePTY = nil
        }
        let closeConnection = activeRunID == runID ? self.closeConnection : nil
        if let closeConnection {
            await closeConnection()
        }
        if activeRunID == runID {
            self.closeConnection = nil
        }
    }

    private func setStdinWriter(
        for runID: UInt64,
        _ writer: @escaping @Sendable ([UInt8]) async throws -> Void
    ) {
        guard activeRunID == runID else { return }
        stdinWriter = writer
    }

    private func setPTYResizer(
        for runID: UInt64,
        _ resizer: @escaping @Sendable (TerminalSize) async throws -> Void
    ) {
        guard activeRunID == runID else { return }
        resizePTY = resizer
    }

    private func setCloseConnection(
        _ closer: @escaping @Sendable () async -> Void,
        for runID: UInt64
    ) {
        guard activeRunID == runID else { return }
        closeConnection = closer
    }

    private func clearState(for runID: UInt64) {
        defer { stoppingRunIDs.remove(runID) }
        guard activeRunID == runID else { return }
        stdinWriter = nil
        resizePTY = nil
        closeConnection = nil
    }

    private static func describe(_ error: Error) -> String {
        let message = String(describing: error)
        let lowercased = message.lowercased()

        if lowercased.contains("authentication") || lowercased.contains("auth") {
            return "认证失败"
        }
        if lowercased.contains("timeout") {
            return "连接超时"
        }
        if lowercased.contains("refused") {
            return "连接被拒绝"
        }
        if lowercased.contains("unreachable") || lowercased.contains("no route") {
            return "主机不可达"
        }
        return message
    }

    private static func isBenignClosure(_ error: Error) -> Bool {
        let lowercased = String(describing: error).lowercased()
        return lowercased.contains("already closed")
            || lowercased.contains("channel closed")
            || lowercased.contains("eof")
    }
}

enum TerminalSessionError: Error {
    case notReady
}

struct TerminalSize: Equatable, Sendable {
    let columns: Int
    let rows: Int
    let pixelWidth: Int
    let pixelHeight: Int

    static let fallback = TerminalSize(columns: 80, rows: 24, pixelWidth: 0, pixelHeight: 0)

    init(columns: Int, rows: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.columns = max(2, columns)
        self.rows = max(2, rows)
        self.pixelWidth = max(0, pixelWidth)
        self.pixelHeight = max(0, pixelHeight)
    }
}
