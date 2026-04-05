import SwiftUI

struct TerminalView: View {
    let server: ServerConfig
    @StateObject private var viewModel: TerminalViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(server: ServerConfig) {
        self.server = server
        _viewModel = StateObject(wrappedValue: TerminalViewModel(server: server))
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
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleScenePhaseChange(newPhase)
        }
        .onChange(of: viewModel.shouldDismissTerminal) { _, shouldDismiss in
            guard shouldDismiss else { return }
            dismiss()
            viewModel.acknowledgeDismissRequest()
        }
        .onDisappear {
            viewModel.disconnect(clearError: true)
        }
        .sheet(isPresented: $viewModel.isShowingLaunchSheet) {
            TerminalLaunchSheet(
                server: server,
                recoverableSessions: viewModel.recoverableSessions,
                latestSnapshot: viewModel.latestSnapshot,
                onResume: { session in
                    viewModel.resumePersistentSession(session)
                },
                onNewPersistentSession: {
                    viewModel.startNewPersistentSession()
                },
                onDirectSession: {
                    viewModel.startDirectSession()
                },
                onCloseTerminal: dismissTerminal
            )
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
            Button(action: dismissTerminal) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.isPersistentSession ? "断开并关闭终端" : "关闭终端")

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

    private func dismissTerminal() {
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
