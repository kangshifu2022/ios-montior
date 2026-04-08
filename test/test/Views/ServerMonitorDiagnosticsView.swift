import Combine
import SwiftUI
import UIKit

struct ServerMonitorDiagnosticsView: View {
    @State private var entries: [ServerMonitorDiagnosticEntry] = ServerMonitorDiagnosticsStore.loadEntries()

    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    var body: some View {
        List {
            Section("怎么看") {
                Text("`ssh-connect` / `ssh-execute` 说明 SSH 连接或远端命令本身失败，优先看网络、端口、认证和服务器负载。")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Text("`offline-grace` 表示本次刷新失败，但应用还在宽限期内，卡片暂时继续维持在线。")
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Text("`offline-transition` 和 `recovered` 才对应设备卡片真正切到离线或重新恢复在线。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if entries.isEmpty {
                Section {
                    Text("还没有监控诊断日志。")
                        .foregroundColor(.secondary)
                } footer: {
                    Text("这里会保留设备监控、SSH 失败、离线判定和恢复事件，用来排查首页设备卡片抖动、间歇掉线和远端命令异常。")
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

                            Text(entry.message)
                                .font(.footnote.monospaced())
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("如果某台设备反复掉线，先按设备名或 host 查 `offline-transition` 前后的 `ssh-connect` / `ssh-execute`，再看是否伴随 `offline-grace` 和 `recovered`。")
                }
            }
        }
        .navigationTitle("监控诊断日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("复制") {
                    UIPasteboard.general.string = ServerMonitorDiagnosticsStore.exportText()
                }
                .disabled(entries.isEmpty)

                Button("清空", role: .destructive) {
                    ServerMonitorDiagnosticsStore.clear()
                }
                .disabled(entries.isEmpty)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ServerMonitorDiagnosticsStore.didChangeNotification)) { _ in
            entries = ServerMonitorDiagnosticsStore.loadEntries()
        }
    }

    private func levelColor(for level: ServerMonitorDiagnosticLevel) -> Color {
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
