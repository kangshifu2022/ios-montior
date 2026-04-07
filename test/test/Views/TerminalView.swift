import SwiftUI

struct TerminalView: View {
    let server: ServerConfig
    @ObservedObject var viewModel: TerminalViewModel
    private let onSuspend: (() -> Void)?
    private let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(
        server: ServerConfig,
        viewModel: TerminalViewModel,
        onSuspend: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.server = server
        self.viewModel = viewModel
        self.onSuspend = onSuspend
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            terminalBackground
                .ignoresSafeArea()

            TerminalSurfaceView(viewModel: viewModel, colorScheme: colorScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(terminalBackground)
        }
        .background(screenBackground)
        .safeAreaInset(edge: .top, spacing: 0) {
            headerBar
        }
        .task {
            viewModel.prepareLaunchIfNeeded()
            viewModel.connectIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
        .onChange(of: viewModel.shouldDismissTerminal) { _, shouldDismiss in
            guard shouldDismiss else { return }
            closeTerminalView()
            viewModel.acknowledgeDismissRequest()
        }
        .sheet(isPresented: $viewModel.isShowingLaunchSheet) {
            TerminalLaunchSheet(
                server: server,
                recoverableSessions: viewModel.recoverableSessions,
                latestSnapshot: viewModel.latestSnapshot,
                remoteTmuxSessions: viewModel.remoteTmuxSessions,
                isRefreshingRemoteTmuxSessions: viewModel.isRefreshingRemoteTmuxSessions,
                remoteTmuxStatusText: viewModel.remoteTmuxStatusText,
                onResume: { session in
                    viewModel.resumePersistentSession(session)
                },
                onStartNamedPersistentSession: { sessionName in
                    viewModel.startPersistentSession(named: sessionName)
                },
                onNewPersistentSession: {
                    viewModel.startNewPersistentSession()
                },
                onDirectSession: {
                    viewModel.startDirectSession()
                },
                onRefreshRemoteTmuxSessions: {
                    viewModel.refreshRemoteTmuxSessions()
                },
                onCloseTerminal: closeTerminalView
            )
            .task {
                viewModel.refreshRemoteTmuxSessionsIfNeeded()
            }
        }
        .alert("终端错误", isPresented: errorPresented) {
            Button("知道了", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.lastError ?? "未知错误")
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button(action: suspendOrCloseTerminal) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.hasSessionToSuspend ? "挂起终端" : "关闭终端")

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.displayTitle)
                    .font(.headline)
                    .lineLimit(1)

                Text(viewModel.sessionSummaryText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if viewModel.isPersistentSession {
                Text("tmux")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(viewModel.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.08))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func suspendOrCloseTerminal() {
        guard viewModel.hasSessionToSuspend, let onSuspend else {
            closeTerminalView()
            return
        }

        onSuspend()
    }

    private func closeTerminalView() {
        if let onClose {
            onClose()
            return
        }

        viewModel.disconnect(clearError: true)
        dismiss()
    }

    private var screenBackground: Color {
        Color(.systemBackground)
    }

    private var terminalBackground: Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.05, green: 0.06, blue: 0.08)
        case .light:
            return Color(red: 0.97, green: 0.98, blue: 0.99)
        @unknown default:
            return Color(.systemBackground)
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.lastError != nil },
            set: { newValue in
                if !newValue {
                    viewModel.clearError()
                }
            }
        )
    }
}
