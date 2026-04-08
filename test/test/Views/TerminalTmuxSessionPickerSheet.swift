import SwiftUI

struct TerminalTmuxSessionPickerSheet: View {
    @ObservedObject var viewModel: TerminalViewModel

    @State private var pendingSelectedSession: TerminalRemoteTmuxSession?

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
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("远端 tmux 会话")
                } footer: {
                    Text("选择后会结束当前终端，并重新连接到对应的 tmux 会话。")
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
                    .disabled(viewModel.isRefreshingRemoteTmuxSessions)
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
}
