import Foundation
import Citadel
import NIOCore
import NIOSSH

actor TerminalSession {
    enum Event: Sendable {
        case connecting(String)
        case connected
        case output(String)
        case error(String)
        case disconnected
    }

    private let server: ServerConfig
    private var stdinWriter: (@Sendable (String) async throws -> Void)?
    private var closeConnection: (@Sendable () async -> Void)?

    init(server: ServerConfig) {
        self.server = server
    }

    func start(onEvent: @escaping @Sendable (Event) async -> Void) async {
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
                    terminalCharacterWidth: 120,
                    terminalRowHeight: 40,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: .init([.ECHO: 1])
                )
            ) { ttyOutput, ttyStdinWriter in
                await self.setStdinWriter { input in
                    try await ttyStdinWriter.write(ByteBuffer(string: input))
                }

                await onEvent(.connected)

                for try await event in ttyOutput {
                    let text: String

                    switch event {
                    case .stdout(let buffer), .stderr(let buffer):
                        text = TerminalANSI.sanitize(String(buffer: buffer))
                    }

                    guard !text.isEmpty else { continue }
                    await onEvent(.output(text))
                }
            }
        } catch is CancellationError {
            await onEvent(.disconnected)
        } catch {
            await onEvent(.error(Self.describe(error)))
            await onEvent(.disconnected)
        }

        clearState()
    }

    func send(_ input: String) async throws {
        guard let stdinWriter else {
            throw TerminalSessionError.notReady
        }
        try await stdinWriter(input)
    }

    func stop() async {
        stdinWriter = nil
        if let closeConnection {
            await closeConnection()
        }
        closeConnection = nil
    }

    private func setStdinWriter(_ writer: @escaping @Sendable (String) async throws -> Void) {
        stdinWriter = writer
    }

    private func clearState() {
        stdinWriter = nil
        closeConnection = nil
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
}

enum TerminalSessionError: Error {
    case notReady
}

private enum TerminalANSI {
    static func sanitize(_ raw: String) -> String {
        guard !raw.isEmpty else { return raw }

        let escape = "\u{001B}"
        var text = raw
            .replacingOccurrences(of: "\u{0007}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let patterns = [
            "\(escape)\\[[0-9;?]*[ -/]*[@-~]",
            "\(escape)\\][^\u{0007}]*\u{0007}",
            "\(escape)[@-_]"
        ]

        for pattern in patterns {
            text = text.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return text
    }
}
