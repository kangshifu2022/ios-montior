import SwiftUI

struct TerminalView: View {
    let server: ServerConfig
    @State private var output: [String] = []
    @State private var input: String = ""
    @State private var isConnected = false
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                    Text("返回")
                }
                Spacer()
                Text(server.name)
                    .fontWeight(.medium)
                Spacer()
                Circle()
                    .fill(isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isConnected ? "已连接" : "未连接")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(output.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(12)
                }
                .background(Color.black)
                .onChange(of: output.count) {
                    proxy.scrollTo(output.count - 1, anchor: .bottom)
                }
            }

            HStack(spacing: 8) {
                Text("$")
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.green)
                TextField("输入命令", text: $input)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .onSubmit { sendCommand() }
                Button(action: sendCommand) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.1))
        }
        .background(Color.black)
        .onAppear {
            inputFocused = true
            output.append("Connecting to \(server.host)...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isConnected = true
                output.append("Connected to \(server.host)")
                output.append("")
            }
        }
    }

    func sendCommand() {
        guard !input.isEmpty else { return }
        let cmd = input
        output.append("$ \(cmd)")
        input = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            output.append("command not found: \(cmd)")
            output.append("")
        }
    }
}
