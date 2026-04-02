import SwiftUI

struct TerminalView: View {
    let server: ServerConfig
    @StateObject private var viewModel: TerminalViewModel
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(server: ServerConfig) {
        self.server = server
        _viewModel = StateObject(wrappedValue: TerminalViewModel(server: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            terminalOutput
            inputBar
        }
        .background(Color.black)
        .task {
            viewModel.connectIfNeeded()
            inputFocused = true
        }
        .onDisappear {
            viewModel.disconnect()
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
                Text(server.name)
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

    private var terminalOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.entries) { entry in
                        Text(entry.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(color(for: entry.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(entry.id)
                    }
                }
                .padding(12)
            }
            .background(Color.black)
            .onChange(of: viewModel.entries.count) {
                if let lastID = viewModel.entries.last?.id {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                terminalControlButton(icon: "clock.arrow.circlepath") {
                    viewModel.moveHistoryBackward()
                    inputFocused = true
                }

                terminalControlButton(icon: "clock") {
                    viewModel.moveHistoryForward()
                    inputFocused = true
                }

                terminalControlButton(icon: "xmark.circle") {
                    viewModel.sendInterrupt()
                }

                terminalControlButton(icon: "trash") {
                    viewModel.clearOutput()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Text(">")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)

                TextField("输入命令", text: $viewModel.input)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit {
                        viewModel.sendCurrentCommand()
                    }

                Button(action: {
                    viewModel.sendCurrentCommand()
                    inputFocused = true
                }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(viewModel.isConnected ? .green : .gray)
                }
                .disabled(!viewModel.isConnected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(white: 0.1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Color.black)
    }

    private func terminalControlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.85))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func color(for kind: TerminalEntry.Kind) -> Color {
        switch kind {
        case .system:
            return Color.white.opacity(0.72)
        case .output:
            return Color.green
        case .error:
            return Color.red.opacity(0.9)
        }
    }
}
