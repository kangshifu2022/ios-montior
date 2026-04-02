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
        VStack(spacing: 0) {
            TerminalSurfaceView(viewModel: viewModel, colorScheme: colorScheme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(terminalBackground)
                .ignoresSafeArea(edges: .top)
            toolBar
        }
        .background(screenBackground)
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
        .alert("终端错误", isPresented: errorPresented) {
            Button("知道了", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.lastError ?? "未知错误")
        }
    }

    private var toolBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                toolButton(icon: "xmark", label: "关闭") {
                    dismiss()
                }

                toolButton(icon: "arrow.clockwise", label: "重连") {
                    viewModel.reconnect()
                }

                toolButton(icon: "xmark.circle", label: "Ctrl+C") {
                    viewModel.sendInterrupt()
                }

                toolButton(icon: "chevron.backward.circle", label: "Esc") {
                    viewModel.sendEscape()
                }

                toolButton(icon: "arrow.right.to.line.compact", label: "Tab") {
                    viewModel.sendTab()
                }

                toolButton(icon: "slash.circle", label: "/") {
                    viewModel.sendSlash()
                }

                toolButton(icon: "rectangle.portrait.and.arrow.right", label: "exit") {
                    viewModel.sendExit()
                }

                toolButton(icon: "arrow.left.to.line", label: "Home") {
                    viewModel.sendHome()
                }

                toolButton(icon: "arrow.right.to.line", label: "End") {
                    viewModel.sendEnd()
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
        .background(toolbarBackground)
    }

    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption)
            .foregroundColor(toolButtonForeground)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(toolButtonBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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

    private var toolbarBackground: Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.09, green: 0.11, blue: 0.14)
        case .light:
            return Color(red: 0.93, green: 0.95, blue: 0.97)
        @unknown default:
            return Color(.secondarySystemBackground)
        }
    }

    private var toolButtonBackground: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        case .light:
            return Color.black.opacity(0.06)
        @unknown default:
            return Color.black.opacity(0.06)
        }
    }

    private var toolButtonForeground: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.88)
        case .light:
            return Color.black.opacity(0.78)
        @unknown default:
            return Color.primary
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
