import SwiftUI

struct TerminalLaunchSheet: View {
    let server: ServerConfig
    let recoverableSessions: [TerminalSavedSession]
    let latestSnapshot: TerminalSavedSession?
    let onResume: (TerminalSavedSession) -> Void
    let onNewPersistentSession: () -> Void
    let onDirectSession: () -> Void
    let onCloseTerminal: () -> Void

    private let relativeFormatter = RelativeDateTimeFormatter()

    var body: some View {
        NavigationStack {
            List {
                if let latestSnapshot, !latestSnapshot.preview.isEmpty {
                    Section("上次本地输出预览") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(latestSnapshot.modeLabel)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Capsule())

                                Text(relativeText(for: latestSnapshot.sortDate))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text(latestSnapshot.preview)
                                .font(.footnote.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(6)
                        }
                        .padding(.vertical, 4)
                    } footer: {
                        Text("这是本地缓存的最近输出，用来帮助你在恢复前判断要不要继续。")
                    }
                }

                if !recoverableSessions.isEmpty {
                    Section("可恢复会话") {
                        ForEach(recoverableSessions) { session in
                            Button {
                                onResume(session)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(session.displayName)
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(relativeText(for: session.sortDate))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    if !session.preview.isEmpty {
                                        Text(session.preview)
                                            .font(.footnote.monospaced())
                                            .foregroundColor(.secondary)
                                            .lineLimit(3)
                                    } else {
                                        Text("远端会话已记录，本地还没有缓存输出。")
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    } footer: {
                        Text("选择后会优先重新附着到之前的 tmux 会话；如果远端同名会话已不存在，会自动新建同名会话。")
                    }
                }

                Section("新建连接") {
                    Button {
                        onNewPersistentSession()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("新建持久 tmux 会话")
                                .foregroundColor(.primary)
                            Text("推荐，用于长任务和 Codex 这类交互助手。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        onDirectSession()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("直接 SSH")
                                .foregroundColor(.primary)
                            Text("兼容性最好，但断开后当前前台任务通常也会结束。")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(server.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭终端") {
                        onCloseTerminal()
                    }
                }
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func relativeText(for date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
