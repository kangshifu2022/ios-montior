import Foundation

enum TerminalDefaultConnectionMode: String, CaseIterable, Identifiable {
    case persistentTmux
    case directSSH

    static let storageKey = "terminal.defaultConnectionMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .persistentTmux:
            return "持久 tmux"
        case .directSSH:
            return "直接 SSH"
        }
    }

    var subtitle: String {
        switch self {
        case .persistentTmux:
            return "推荐，意外断开后可回到之前的远端会话。"
        case .directSSH:
            return "兼容性最好，但断开后当前终端任务通常也会结束。"
        }
    }
}

enum TerminalRestorePolicy: String, CaseIterable, Identifiable {
    case askEveryTime
    case resumeMostRecent
    case alwaysStartNew

    static let storageKey = "terminal.restorePolicy"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .askEveryTime:
            return "每次询问"
        case .resumeMostRecent:
            return "自动恢复最近会话"
        case .alwaysStartNew:
            return "总是新建"
        }
    }

    var subtitle: String {
        switch self {
        case .askEveryTime:
            return "进入终端后先探测远端 tmux；检测到会话时再给出恢复选择。"
        case .resumeMostRecent:
            return "检测到可恢复会话时直接接回最近一次。"
        case .alwaysStartNew:
            return "忽略旧会话，直接按默认模式新开。"
        }
    }
}

enum TerminalSavedSessionKind: String, Codable, Hashable, Sendable {
    case directSSH
    case persistentTmux
}

struct TerminalRemoteTmuxSession: Identifiable, Hashable, Sendable {
    var name: String
    var windowCount: Int?
    var isAttached: Bool

    var id: String { name }

    var detailText: String {
        var fragments: [String] = []

        if let windowCount {
            fragments.append("\(windowCount) 个窗口")
        }
        if isAttached {
            fragments.append("当前已附着")
        }

        return fragments.joined(separator: " · ")
    }
}

struct TerminalSavedSession: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var serverID: UUID
    var serverName: String
    var kind: TerminalSavedSessionKind
    var sessionName: String?
    var title: String
    var createdAt: Date
    var lastAttachedAt: Date
    var lastOutputAt: Date
    var allowsResume: Bool
    var scrollback: Data
    var preview: String

    var isRecoverable: Bool {
        kind == .persistentTmux && allowsResume && sessionName?.isEmpty == false
    }

    var displayName: String {
        if let sessionName, !sessionName.isEmpty {
            return sessionName
        }

        switch kind {
        case .persistentTmux:
            return title
        case .directSSH:
            return "直连 SSH"
        }
    }

    var modeLabel: String {
        switch kind {
        case .persistentTmux:
            return "tmux"
        case .directSSH:
            return "SSH"
        }
    }

    var sortDate: Date {
        max(lastAttachedAt, lastOutputAt)
    }
}
