import Combine
import SwiftUI
import UIKit

struct TerminalDiagnosticsView: View {
    @State private var entries: [TerminalDiagnosticEntry] = TerminalDiagnosticsStore.loadEntries()

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        List {
            if entries.isEmpty {
                Section {
                    Text("还没有终端诊断日志。")
                        .foregroundColor(.secondary)
                } footer: {
                    Text("这里会保留最近的终端连接、断联、恢复决策和错误事件，便于排查闪退或 SSH 断流问题。")
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Text(timestampFormatter.string(from: entry.timestamp))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)

                                Text(entry.level.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(levelColor(for: entry.level))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(levelColor(for: entry.level).opacity(0.12))
                                    .clipShape(Capsule())

                                Text(entry.category)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }

                            if let serverSummary = entry.serverSummary, !serverSummary.isEmpty {
                                Text(serverSummary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            if let sessionName = entry.sessionName, !sessionName.isEmpty {
                                Text("session: \(sessionName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Text(entry.message)
                                .font(.footnote.monospaced())
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("日志只保存在本机，用于定位终端崩溃、SSH 断联、tmux 恢复和前后台切换问题。")
                }
            }
        }
        .navigationTitle("终端诊断日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("复制") {
                    UIPasteboard.general.string = TerminalDiagnosticsStore.exportText()
                }
                .disabled(entries.isEmpty)

                Button("清空", role: .destructive) {
                    TerminalDiagnosticsStore.clear()
                }
                .disabled(entries.isEmpty)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: TerminalDiagnosticsStore.didChangeNotification)) { _ in
            entries = TerminalDiagnosticsStore.loadEntries()
        }
    }

    private func levelColor(for level: TerminalDiagnosticLevel) -> Color {
        switch level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
