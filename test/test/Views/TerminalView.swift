import SwiftUI
import UIKit

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
        ZStack(alignment: .top) {
            terminalBackground
                .ignoresSafeArea()

            TerminalSurfaceView(viewModel: viewModel, colorScheme: colorScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(terminalBackground)

            if let connectionNoticeText = viewModel.connectionNoticeText {
                TerminalConnectionStatusCard(
                    title: viewModel.showsConnectionFailureNotice ? "连接失败" : viewModel.statusText,
                    message: connectionNoticeText,
                    showsProgress: viewModel.showsConnectionProgressNotice,
                    isError: viewModel.showsConnectionFailureNotice
                )
                .padding(.horizontal, 16)
                .padding(.top, 56)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(.top, 12)
                .padding(.trailing, 16)
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.connectionNoticeText)
        .background(screenBackground)
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
        .onChange(of: viewModel.shouldSuspendTerminal) { _, shouldSuspend in
            guard shouldSuspend else { return }
            suspendTerminalView()
            viewModel.acknowledgeSuspendRequest()
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
        .fullScreenCover(isPresented: $viewModel.isShowingTmuxSessionPicker, onDismiss: {
            viewModel.restoreTerminalKeyboardFocus()
        }) {
            TerminalTmuxSessionPickerSheet(viewModel: viewModel)
        }
        .onChange(of: viewModel.isShowingTmuxSessionPicker) { _, isPresented in
            guard isPresented else { return }
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder),
                to: nil,
                from: nil,
                for: nil
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

    private var closeButton: some View {
        Button(action: closeTerminalView) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("关闭终端")
    }

    private func suspendTerminalView() {
        guard viewModel.hasSessionToSuspend, let onSuspend else {
            closeTerminalView()
            return
        }

        onSuspend()
    }

    private func closeTerminalView() {
        if let onClose {
            onClose()
            dismiss()
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
            get: { viewModel.lastError != nil && viewModel.lastError != viewModel.lastConnectionIssueText },
            set: { newValue in
                if !newValue {
                    viewModel.clearError()
                }
            }
        )
    }
}

private struct TerminalConnectionStatusCard: View {
    let title: String
    let message: String
    let showsProgress: Bool
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if showsProgress {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.primary)
            } else {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isError ? Color.red : Color.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isError ? Color.red.opacity(0.16) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
    }
}
