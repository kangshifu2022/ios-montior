import Foundation
import Citadel
import NIOCore
import NIOSSH

private let shellCompatibilityExecThreshold = 8 * 1024

struct TerminalRemoteTmuxSnapshot: Sendable {
    var sessions: [TerminalRemoteTmuxSession]
    var notice: String?
}

struct TerminalRemoteTmuxDeleteResult: Sendable {
    enum Status: Sendable {
        case deleted
        case alreadyMissing
        case tmuxUnavailable
    }

    var status: Status
    var notice: String?
}

struct TerminalRemoteTmuxCreateResult: Sendable {
    enum Status: Sendable {
        case created
        case alreadyExists
        case tmuxUnavailable
    }

    var status: Status
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
        let result = await execute(config: config, script: listSessionsScript, maxResponseSize: 1 << 16)
        switch result {
        case .success(let output):
            let snapshot = parseTmuxSnapshot(output)
            TerminalDiagnosticsStore.record(
                "tmux probe completed, sessions=\(snapshot.sessions.count), notice=\(snapshot.notice ?? "none")",
                category: "tmux-probe",
                server: config
            )
            return .success(snapshot)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func deleteSession(named sessionName: String, config: ServerConfig) async -> Result<TerminalRemoteTmuxDeleteResult, TerminalRemoteTmuxQueryError> {
        TerminalDiagnosticsStore.record(
            "delete remote tmux session \(sessionName)",
            category: "tmux-probe",
            server: config
        )

        let result = await execute(
            config: config,
            script: deleteSessionScript(for: sessionName),
            maxResponseSize: 1 << 14
        )

        switch result {
        case .success(let output):
            let parsed = parseTmuxDeleteResult(output, sessionName: sessionName)
            switch parsed {
            case .success(let deleteResult):
                TerminalDiagnosticsStore.record(
                    "tmux delete completed, status=\(describe(deleteResult.status)), notice=\(deleteResult.notice ?? "none")",
                    category: "tmux-probe",
                    server: config
                )
            case .failure(let error):
                TerminalDiagnosticsStore.record(
                    "tmux delete parse failed: \(error.message)",
                    level: .warning,
                    category: "tmux-probe",
                    server: config
                )
            }
            return parsed
        case .failure(let error):
            return .failure(error)
        }
    }

    static func createSession(named sessionName: String, config: ServerConfig) async -> Result<TerminalRemoteTmuxCreateResult, TerminalRemoteTmuxQueryError> {
        TerminalDiagnosticsStore.record(
            "create remote tmux session \(sessionName)",
            category: "tmux-probe",
            server: config
        )

        let result = await execute(
            config: config,
            script: createSessionScript(for: sessionName),
            maxResponseSize: 1 << 14
        )

        switch result {
        case .success(let output):
            let parsed = parseTmuxCreateResult(output, sessionName: sessionName)
            switch parsed {
            case .success(let createResult):
                TerminalDiagnosticsStore.record(
                    "tmux create completed, status=\(describe(createResult.status)), notice=\(createResult.notice ?? "none")",
                    category: "tmux-probe",
                    server: config
                )
            case .failure(let error):
                TerminalDiagnosticsStore.record(
                    "tmux create parse failed: \(error.message)",
                    level: .warning,
                    category: "tmux-probe",
                    server: config
                )
            }
            return parsed
        case .failure(let error):
            return .failure(error)
        }
    }
}

private func execute(
    config: ServerConfig,
    script: String,
    maxResponseSize: Int
) async -> Result<String, TerminalRemoteTmuxQueryError> {
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
            let output = try await runRemoteScript(
                script,
                with: client,
                maxResponseSize: maxResponseSize,
                config: config
            )
            try? await client.close()
            return .success(String(buffer: output))
        } catch {
            try? await client.close()
            TerminalDiagnosticsStore.record(
                "tmux command execute failed: \(describeTmuxError(error))",
                level: .warning,
                category: "tmux-probe",
                server: config
            )
            return .failure(TerminalRemoteTmuxQueryError(message: describeTmuxError(error)))
        }
    } catch {
        TerminalDiagnosticsStore.record(
            "tmux command connect failed: \(describeTmuxError(error))",
            level: .warning,
            category: "tmux-probe",
            server: config
        )
        return .failure(TerminalRemoteTmuxQueryError(message: describeTmuxError(error)))
    }
}

private func runRemoteScript(
    _ script: String,
    with client: SSHClient,
    maxResponseSize: Int,
    config: ServerConfig
) async throws -> ByteBuffer {
    let prefersShellCompatibility = script.utf8.count >= shellCompatibilityExecThreshold

    do {
        return try await client.executeCommand(
            script,
            maxResponseSize: maxResponseSize,
            mergeStreams: true,
            inShell: prefersShellCompatibility
        )
    } catch {
        let lowercased = String(describing: error).lowercased()
        let shouldRetryInShell = lowercased.contains("tcpshutdown")
            || lowercased.contains("channel closed")
            || lowercased.contains("channelclosed")

        guard !prefersShellCompatibility, shouldRetryInShell else {
            throw error
        }

        TerminalDiagnosticsStore.record(
            "tmux exec request closed unexpectedly; retrying in shell compatibility mode",
            level: .info,
            category: "tmux-probe",
            server: config
        )

        return try await client.executeCommand(
            script,
            maxResponseSize: maxResponseSize,
            mergeStreams: true,
            inShell: true
        )
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

private func parseTmuxDeleteResult(
    _ output: String,
    sessionName: String
) -> Result<TerminalRemoteTmuxDeleteResult, TerminalRemoteTmuxQueryError> {
    let lines = output.components(separatedBy: .newlines)
    var status = "unknown"
    var messageLines: [String] = []
    var index = 0

    while index < lines.count {
        let line = lines[index]

        if line == "=TMUX_STATUS=", index + 1 < lines.count {
            status = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 2
            continue
        }

        if line == "=TMUX_MESSAGE=" {
            messageLines = Array(lines[(index + 1)...])
            break
        }

        index += 1
    }

    let message = messageLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercasedOutput = output.lowercased()

    switch status {
    case "ok":
        return .success(
            TerminalRemoteTmuxDeleteResult(
                status: .deleted,
                notice: "已删除远端 tmux 会话“\(sessionName)”。"
            )
        )
    case "missing_session":
        return .success(
            TerminalRemoteTmuxDeleteResult(
                status: .alreadyMissing,
                notice: "tmux 会话“\(sessionName)”已不存在。"
            )
        )
    case "missing_tmux":
        return .success(
            TerminalRemoteTmuxDeleteResult(
                status: .tmuxUnavailable,
                notice: "服务器未安装 tmux，目标会话已视为不存在。"
            )
        )
    case "failed":
        return .failure(
            TerminalRemoteTmuxQueryError(
                message: message.isEmpty ? "删除 tmux 会话失败" : message
            )
        )
    default:
        if lowercasedOutput.contains("can't find session") || lowercasedOutput.contains("no server running") {
            return .success(
                TerminalRemoteTmuxDeleteResult(
                    status: .alreadyMissing,
                    notice: "tmux 会话“\(sessionName)”已不存在。"
                )
            )
        }

        if !message.isEmpty {
            return .failure(TerminalRemoteTmuxQueryError(message: message))
        }

        return .failure(TerminalRemoteTmuxQueryError(message: "未能识别删除 tmux 会话的返回结果。"))
    }
}

private func parseTmuxCreateResult(
    _ output: String,
    sessionName: String
) -> Result<TerminalRemoteTmuxCreateResult, TerminalRemoteTmuxQueryError> {
    let lines = output.components(separatedBy: .newlines)
    var status = "unknown"
    var messageLines: [String] = []
    var index = 0

    while index < lines.count {
        let line = lines[index]

        if line == "=TMUX_STATUS=", index + 1 < lines.count {
            status = lines[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 2
            continue
        }

        if line == "=TMUX_MESSAGE=" {
            messageLines = Array(lines[(index + 1)...])
            break
        }

        index += 1
    }

    let message = messageLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let lowercasedOutput = output.lowercased()

    switch status {
    case "ok":
        return .success(
            TerminalRemoteTmuxCreateResult(
                status: .created,
                notice: "已新建远端 tmux 会话“\(sessionName)”。"
            )
        )
    case "session_exists":
        return .success(
            TerminalRemoteTmuxCreateResult(
                status: .alreadyExists,
                notice: "tmux 会话“\(sessionName)”已存在，请换一个名称。"
            )
        )
    case "missing_tmux":
        return .success(
            TerminalRemoteTmuxCreateResult(
                status: .tmuxUnavailable,
                notice: "服务器未安装 tmux，无法创建新会话。"
            )
        )
    case "failed":
        return .failure(
            TerminalRemoteTmuxQueryError(
                message: message.isEmpty ? "新建 tmux 会话失败" : message
            )
        )
    default:
        if lowercasedOutput.contains("duplicate session") || lowercasedOutput.contains("session already exists") {
            return .success(
                TerminalRemoteTmuxCreateResult(
                    status: .alreadyExists,
                    notice: "tmux 会话“\(sessionName)”已存在，请换一个名称。"
                )
            )
        }

        if !message.isEmpty {
            return .failure(TerminalRemoteTmuxQueryError(message: message))
        }

        return .failure(TerminalRemoteTmuxQueryError(message: "未能识别新建 tmux 会话的返回结果。"))
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

private func describe(_ status: TerminalRemoteTmuxDeleteResult.Status) -> String {
    switch status {
    case .deleted:
        return "deleted"
    case .alreadyMissing:
        return "already-missing"
    case .tmuxUnavailable:
        return "tmux-unavailable"
    }
}

private func describe(_ status: TerminalRemoteTmuxCreateResult.Status) -> String {
    switch status {
    case .created:
        return "created"
    case .alreadyExists:
        return "already-exists"
    case .tmuxUnavailable:
        return "tmux-unavailable"
    }
}

private func describeTmuxError(_ error: Error) -> String {
    let message = String(describing: error)
    let lowercased = message.lowercased()

    if lowercased.contains("authentication") || lowercased.contains("auth") {
        return "认证失败"
    }
    if lowercased.contains("tcpshutdown") {
        return "服务器在执行命令时主动关闭了 SSH 会话"
    }
    if lowercased.contains("channel closed") || lowercased.contains("channelclosed") {
        return "SSH 通道在执行命令时被意外关闭"
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

private func deleteSessionScript(for sessionName: String) -> String {
    let quotedSessionName = singleQuoted(sessionName)
    return """
    if ! command -v tmux >/dev/null 2>&1; then
      echo "=TMUX_STATUS="
      echo "missing_tmux"
      exit 0
    fi

    OUTPUT="$(tmux kill-session -t \(quotedSessionName) 2>&1)"
    STATUS=$?

    if [ "$STATUS" -eq 0 ]; then
      echo "=TMUX_STATUS="
      echo "ok"
      exit 0
    fi

    case "$OUTPUT" in
      *"can't find session"*|*"no server running"*)
        echo "=TMUX_STATUS="
        echo "missing_session"
        exit 0
        ;;
    esac

    echo "=TMUX_STATUS="
    echo "failed"
    echo "=TMUX_MESSAGE="
    printf '%s\n' "$OUTPUT"
    exit 0
    """
}

private func createSessionScript(for sessionName: String) -> String {
    let quotedSessionName = singleQuoted(sessionName)
    return """
    if ! command -v tmux >/dev/null 2>&1; then
      echo "=TMUX_STATUS="
      echo "missing_tmux"
      exit 0
    fi

    if tmux has-session -t \(quotedSessionName) 2>/dev/null; then
      echo "=TMUX_STATUS="
      echo "session_exists"
      exit 0
    fi

    OUTPUT="$(tmux new-session -d -s \(quotedSessionName) 2>&1)"
    STATUS=$?

    if [ "$STATUS" -eq 0 ]; then
      echo "=TMUX_STATUS="
      echo "ok"
      exit 0
    fi

    case "$OUTPUT" in
      *"duplicate session"*|*"session already exists"*)
        echo "=TMUX_STATUS="
        echo "session_exists"
        exit 0
        ;;
    esac

    echo "=TMUX_STATUS="
    echo "failed"
    echo "=TMUX_MESSAGE="
    printf '%s\n' "$OUTPUT"
    exit 0
    """
}

private func singleQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
}
