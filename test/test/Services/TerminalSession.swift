import Foundation
import Citadel
import NIOCore
import NIOSSH

actor TerminalSession {
    enum Event: Sendable {
        case connecting(String)
        case connected
        case output([UInt8])
        case error(String)
        case disconnected
    }

    private let server: ServerConfig
    private var stdinWriter: (@Sendable ([UInt8]) async throws -> Void)?
    private var resizePTY: (@Sendable (TerminalSize) async throws -> Void)?
    private var closeConnection: (@Sendable () async -> Void)?
    private var isStopping = false

    init(server: ServerConfig) {
        self.server = server
    }

    func start(
        terminalSize: TerminalSize,
        bootstrapCommand: String? = nil,
        onEvent: @escaping @Sendable (Event) async -> Void
    ) async {
        isStopping = false
        await onEvent(.connecting(server.host))

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

            closeConnection = {
                try? await client.close()
            }

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
                self.setStdinWriter { input in
                    try await ttyStdinWriter.write(ByteBuffer(bytes: input))
                }
                self.setPTYResizer { size in
                    try await ttyStdinWriter.changeSize(
                        cols: size.columns,
                        rows: size.rows,
                        pixelWidth: size.pixelWidth,
                        pixelHeight: size.pixelHeight
                    )
                }

                await onEvent(.connected)

                if let bootstrapCommand, !bootstrapCommand.isEmpty {
                    try await ttyStdinWriter.write(ByteBuffer(bytes: Array(bootstrapCommand.utf8)))
                }

                for try await event in ttyOutput {
                    let bytes: [UInt8]
                    switch event {
                    case .stdout(let buffer), .stderr(let buffer):
                        bytes = Array(buffer.readableBytesView)
                    }
                    guard !bytes.isEmpty else { continue }
                    await onEvent(.output(bytes))
                }
            }
        } catch is CancellationError {
            await onEvent(.disconnected)
        } catch {
            if !isStopping, !Self.isBenignClosure(error) {
                await onEvent(.error(Self.describe(error)))
            }
            await onEvent(.disconnected)
        }

        clearState()
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
        isStopping = true
        stdinWriter = nil
        resizePTY = nil
        if let closeConnection {
            await closeConnection()
        }
        closeConnection = nil
    }

    private func setStdinWriter(_ writer: @escaping @Sendable ([UInt8]) async throws -> Void) {
        stdinWriter = writer
    }

    private func setPTYResizer(_ resizer: @escaping @Sendable (TerminalSize) async throws -> Void) {
        resizePTY = resizer
    }

    private func clearState() {
        stdinWriter = nil
        resizePTY = nil
        closeConnection = nil
        isStopping = false
    }

    private static func describe(_ error: Error) -> String {
        let message = String(describing: error)
        let lowercased = message.lowercased()

        if lowercased.contains("authentication") || lowercased.contains("auth") {
            return "authentication failed"
        }
        if lowercased.contains("timeout") {
            return "connection timed out"
        }
        if lowercased.contains("refused") {
            return "connection refused"
        }
        if lowercased.contains("unreachable") || lowercased.contains("no route") {
            return "host unreachable"
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
