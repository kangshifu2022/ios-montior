import SwiftUI

struct TerminalView: View {
    let server: ServerConfig
    @StateObject private var viewModel: TerminalViewModel
    @Environment(\.dismiss) private var dismiss

    init(server: ServerConfig) {
        self.server = server
        _viewModel = StateObject(wrappedValue: TerminalViewModel(server: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            TerminalSurfaceView(viewModel: viewModel)
                .background(Color.black)
            toolBar
        }
        .background(Color.black)
        .task {
            viewModel.connectIfNeeded()
        }
        .onDisappear {
            viewModel.disconnect()
        }
        .alert("终端错误", isPresented: errorPresented) {
            Button("知道了", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.lastError ?? "未知错误")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: { dismiss() }) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
            }
            .foregroundColor(.primary)

            Spacer()

            VStack(spacing: 2) {
                Text(viewModel.displayTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("\(server.username)@\(server.host):\(server.port)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(viewModel.isConnected ? Color.green : (viewModel.isConnecting ? Color.orange : Color.red))
                    .frame(width: 8, height: 8)
                Text(viewModel.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private var toolBar: some View {
        HStack(spacing: 12) {
            toolButton(icon: "arrow.clockwise", label: "重连") {
                viewModel.reconnect()
            }

            toolButton(icon: "xmark.circle", label: "Ctrl+C") {
                viewModel.sendInterrupt()
            }

            toolButton(icon: "chevron.backward.circle", label: "Esc") {
                viewModel.sendEscape()
            }

            toolButton(icon: "arrow.right.to.line", label: "Tab") {
                viewModel.sendTab()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }

    private func toolButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
