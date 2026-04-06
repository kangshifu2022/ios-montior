import Foundation
import Citadel
import NIOCore
import NIOSSH

struct TerminalRemoteTmuxSnapshot: Sendable {
    var sessions: [TerminalRemoteTmuxSession]
    var notice: String?
}

struct TerminalRemoteTmuxQueryError: Error, Sendable {
    var message: String
}

enum TerminalTmuxService {
    static func fetchSessions(config: ServerConfig) async -> Result<TerminalRemoteTmuxSnapshot, TerminalRemoteTmuxQueryError> {
        TerminalDiagnosticsStore.record(
            "fetch remote tmux sessions",
            category: "tmux-probe",
            server: config
        )
        let algorithms = SSHAlgorithms.all

        do {
            let client = try await SSHClient.connect(
                host: config.host,
                port: config.port,
                authenticationMethod: .passwordBased(
                    username: config.username,
                    password: config.password
                ),
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: algorithms,
                protocolOptions: [
                    .maximumPacketSize(1 << 20)
                ]
            )

            do {
                let output = try await client.executeCommand(
                    listSessionsScript,
                    maxResponseSize: 1 << 16,
                    mergeStreams: true
                )
                try? await client.close()
                let snapshot = parseTmuxSnapshot(String(buffer: output))
                TerminalDiagnosticsStore.record(
                    "tmux probe completed, sessions=\(snapshot.sessions.count), notice=\(snapshot.notice ?? "none")",
                    category: "tmux-probe",
                    server: config
                )
                return .success(snapshot)
            } catch {
                try? await client.close()
                TerminalDiagnosticsStore.record(
                    "tmux probe execute failed: \(describeTmuxError(error))",
                    level: .warning,
                    category: "tmux-probe",
                    server: config
                )
                return .failure(TerminalRemoteTmuxQueryError(message: describeTmuxError(error)))
            }
        } catch {
            TerminalDiagnosticsStore.record(
                "tmux probe connect failed: \(describeTmuxError(error))",
                level: .warning,
                category: "tmux-probe",
                server: config
            )
            return .failure(TerminalRemoteTmuxQueryError(message: describeTmuxError(error)))
        }
    }
}

private func parseTmuxSnapshot(_ output: String) -> TerminalRemoteTmuxSnapshot {
    let lines = output.components(separatedBy: .newlines)
    var status = "unknown"
    var sessionLines: [String] = []
    var index = 0

    while index < lines.count {
        let line = lines[index]

        if line == "=TMUX_STATUS=", index + 1 < lines.count {
            status = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 2
            continue
        }

        if line == "=TMUX_SESSIONS=" {
            sessionLines = Array(lines[(index + 1)...])
            break
        }

        index += 1
    }

    let sessions = sessionLines
        .compactMap(parseTmuxSession)
        .sorted { lhs, rhs in
            if lhs.isAttached != rhs.isAttached {
                return lhs.isAttached && !rhs.isAttached
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

    switch status {
    case "missing":
        return TerminalRemoteTmuxSnapshot(
            sessions: [],
            notice: "服务器未安装 tmux，无法读取远端会话列表。"
        )
    case "empty":
        return TerminalRemoteTmuxSnapshot(
            sessions: [],
            notice: "远端暂时没有 tmux 会话。"
        )
    case "ok":
        return TerminalRemoteTmuxSnapshot(
            sessions: sessions,
            notice: sessions.isEmpty ? "远端没有可附着的 tmux 会话。" : nil
        )
    default:
        return TerminalRemoteTmuxSnapshot(
            sessions: sessions,
            notice: sessions.isEmpty ? "未能识别远端 tmux 列表返回内容。" : nil
        )
    }
}

private func parseTmuxSession(_ line: String) -> TerminalRemoteTmuxSession? {
    guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }

    let fields = line.components(separatedBy: "\t")
    guard let firstField = fields.first else { return nil }

    let name = firstField.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return nil }

    let windowCount = fields.count > 1 ? Int(fields[1].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    let attachedCount = fields.count > 2 ? Int(fields[2].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 : 0

    return TerminalRemoteTmuxSession(
        name: name,
        windowCount: windowCount,
        isAttached: attachedCount > 0
    )
}

private func describeTmuxError(_ error: Error) -> String {
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

private let listSessionsScript = """
if ! command -v tmux >/dev/null 2>&1; then
  echo "=TMUX_STATUS="
  echo "missing"
  exit 0
fi

SESSIONS="$(tmux list-sessions -F '#{session_name}\t#{session_windows}\t#{session_attached}' 2>/dev/null || true)"

if [ -z "$SESSIONS" ]; then
  echo "=TMUX_STATUS="
  echo "empty"
  exit 0
fi

echo "=TMUX_STATUS="
echo "ok"
echo "=TMUX_SESSIONS="
printf '%s\n' "$SESSIONS"
exit 0
"""
