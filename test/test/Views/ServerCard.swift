import SwiftUI

struct ServerCard: View {
    let config: ServerConfig
    @ObservedObject var store: ServerStore
    var onOpenDetail: (() -> Void)? = nil
    @State private var showTerminal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: openDetail) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Divider()
                    detailSummary
                }
            }
            .buttonStyle(.plain)

            Divider()

            HStack(spacing: 10) {
                Button {
                    Task {
                        await store.refreshServer(config, forceDynamic: true)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text(isRefreshing ? "连接中..." : "重新连接")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .foregroundColor(.primary)
                .disabled(isRefreshing)
                .opacity(isRefreshing ? 0.6 : 1)
                
                Button(action: { showTerminal = true }) {
                    HStack {
                        Image(systemName: "terminal")
                        Text("进入终端")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .foregroundColor(.primary)
                .disabled(stats?.isOnline != true || isRefreshing)
                .opacity(stats?.isOnline == true && !isRefreshing ? 1 : 0.4)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        .fullScreenCover(isPresented: $showTerminal) {
            TerminalView(server: config)
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: stats?.routerInfo.isRouter == true ? "wifi.router" : "server.rack")
                .font(.title2)
            Text(config.name)
                .font(.headline)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()

            if isRefreshing {
                ProgressView()
                    .scaleEffect(0.8)
            }

            if let stats {
                Text(stats.isOnline ? "online" : "offline")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(stats.isOnline ? .green : .red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(stats.isOnline ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                    )

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down").font(.caption2)
                    Text(stats.downloadSpeed).font(.caption)
                    Image(systemName: "arrow.up").font(.caption2)
                    Text(stats.uploadSpeed).font(.caption)
                }
                .foregroundColor(.secondary)
            } else {
                Text(isRefreshing ? "刷新中" : "暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailSummary: some View {
        if let s = stats, s.isOnline {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("hostname \(s.hostname)")
                    Text("cpu \(s.cpuModel)")
                    Text("\(s.cpuCores) cores · \(s.memTotal) MB")
                    Text(s.uptime)
                    if s.routerInfo.isRouter {
                        Text("接入设备: \(s.routerInfo.connectedDevices.count) 台")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                Spacer()

                VStack(spacing: 8) {
                    UsageBar(label: "CPU", value: s.cpuUsage, color: .blue)
                    UsageBar(label: "MEM", value: s.memUsage, color: .green)
                    UsageBar(label: "DISK", value: s.diskUsage, color: .purple)
                }
                .frame(width: 160)
            }

            if !s.diagnostics.isEmpty || !s.statusMessage.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !s.statusMessage.isEmpty {
                        Text("状态: \(s.statusMessage)")
                    }
                    ForEach(s.diagnostics, id: \.self) { item in
                        Text(item)
                    }
                }
                .font(.caption2)
                .foregroundColor(.orange)
                .padding(.top, 4)
            }
        } else if let stats {
            VStack(alignment: .leading, spacing: 4) {
                Text(stats.statusMessage.isEmpty ? "连接失败" : stats.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if !stats.diagnostics.isEmpty {
                    ForEach(stats.diagnostics, id: \.self) { item in
                        Text(item)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
                if !stats.rawOutput.isEmpty {
                    Text(stats.rawOutput)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(6)
                }
            }
            .padding(.vertical, 8)
        } else {
            HStack {
                Spacer()
                ProgressView("首次连接中...")
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    private func openDetail() {
        onOpenDetail?()
    }

    private var stats: ServerStats? {
        store.stats(for: config)
    }

    private var isRefreshing: Bool {
        store.isRefreshing(config.id)
    }
}
