import SwiftUI

struct TerminalTmuxSessionPickerSheet: View {
    @ObservedObject var viewModel: TerminalViewModel

    @State private var pendingSelectedSession: TerminalRemoteTmuxSession?
    @State private var pendingDeletedSession: TerminalRemoteTmuxSession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if viewModel.isRefreshingRemoteTmuxSessions && viewModel.remoteTmuxSessions.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在读取服务器上的 tmux 会话…")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let remoteTmuxStatusText = viewModel.remoteTmuxStatusText,
                       !remoteTmuxStatusText.isEmpty {
                        Text(remoteTmuxStatusText)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    if !viewModel.isRefreshingRemoteTmuxSessions,
                       viewModel.remoteTmuxSessions.isEmpty,
                       (viewModel.remoteTmuxStatusText?.isEmpty ?? true) {
                        Text("远端没有可附着的 tmux 会话。")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    ForEach(viewModel.remoteTmuxSessions) { session in
                        HStack(spacing: 12) {
                            Button {
                                pendingSelectedSession = session
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        if !session.detailText.isEmpty {
                                            Text(session.detailText)
                                                .font(.footnote)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(sessionActionsLocked)

                            Button(role: .destructive) {
                                pendingDeletedSession = session
                            } label: {
                                Group {
                                    if viewModel.deletingRemoteTmuxSessionName == session.name {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "trash")
                                            .font(.body.weight(.semibold))
                                    }
                                }
                                .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.borderless)
                            .disabled(sessionActionsLocked)
                        }
                    }
                } header: {
                    Text("远端 tmux 会话")
                } footer: {
                    Text("点选会进入对应会话；右侧删除按钮会从服务器上移除该 tmux 会话。")
                }
            }
            .navigationTitle("Tmux")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        viewModel.isShowingTmuxSessionPicker = false
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("刷新") {
                        viewModel.refreshRemoteTmuxSessions()
                    }
                    .disabled(sessionActionsLocked)
                }
            }
        }
        .task {
            viewModel.refreshRemoteTmuxSessions()
        }
        .alert("重新连接到 tmux", isPresented: sessionSwitchConfirmationPresented) {
            Button("重新连接") {
                guard let pendingSelectedSession else { return }
                viewModel.switchToRemoteTmuxSession(named: pendingSelectedSession.name)
                self.pendingSelectedSession = nil
            }

            Button("取消", role: .cancel) {
                pendingSelectedSession = nil
            }
        } message: {
            Text("将结束当前终端会话，并重新连接到 tmux 会话“\(pendingSelectedSessionName)”。当前未托管在 tmux 中的前台任务可能会中断。")
        }
        .confirmationDialog(
            "删除远端 tmux 会话",
            isPresented: deleteSessionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除会话", role: .destructive) {
                guard let pendingDeletedSession else { return }
                viewModel.deleteRemoteTmuxSession(named: pendingDeletedSession.name)
                self.pendingDeletedSession = nil
            }

            Button("取消", role: .cancel) {
                pendingDeletedSession = nil
            }
        } message: {
            Text(deleteConfirmationMessage)
        }
    }

    private var sessionSwitchConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingSelectedSession != nil },
            set: { isPresented in
                if !isPresented {
                    pendingSelectedSession = nil
                }
            }
        )
    }

    private var pendingSelectedSessionName: String {
        pendingSelectedSession?.name ?? "所选会话"
    }

    private var deleteSessionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletedSession != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletedSession = nil
                }
            }
        )
    }

    private var deleteConfirmationMessage: String {
        guard let pendingDeletedSession else {
            return "将从服务器上删除所选 tmux 会话。"
        }

        if viewModel.activePersistentSessionName == pendingDeletedSession.name {
            return "将从服务器上删除 tmux 会话“\(pendingDeletedSession.name)”。如果这正是当前终端附着的会话，当前终端会被关闭。"
        }

        return "将从服务器上删除 tmux 会话“\(pendingDeletedSession.name)”。该操作会立即结束这个远端会话。"
    }

    private var sessionActionsLocked: Bool {
        viewModel.isRefreshingRemoteTmuxSessions || viewModel.deletingRemoteTmuxSessionName != nil
    }
}
