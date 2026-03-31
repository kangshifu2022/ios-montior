import SwiftUI

struct ServerCard: View {
    let config: ServerConfig
    @State private var stats: ServerStats? = nil
    @State private var isLoading = true
    @State private var showTerminal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 顶部
            HStack {
                Image(systemName: "server.rack")
                    .font(.title2)
                Text(config.name)
                    .font(.headline)
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(stats?.isOnline == true ? "online" : "offline")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(stats?.isOnline == true ? .green : .red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(stats?.isOnline == true ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                        )
                    
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down").font(.caption2)
                        Text(stats?.downloadSpeed ?? "0k/s").font(.caption)
                        Image(systemName: "arrow.up").font(.caption2)
                        Text(stats?.uploadSpeed ?? "0k/s").font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Divider()

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView("获取数据中...")
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if let s = stats, s.isOnline {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("hostname \(s.hostname)")
                        Text("cpu \(s.cpuModel)")
                        Text("\(s.cpuCores) cores · \(s.memTotal) MB")
                        Text(s.uptime)
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
            } else {
                Text("连接失败")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            }

            Divider()

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
            .disabled(stats?.isOnline != true)
            .opacity(stats?.isOnline == true ? 1 : 0.4)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
        .fullScreenCover(isPresented: $showTerminal) {
            TerminalView(server: config)
        }
        .onAppear {
            fetchData()
        }
    }

    func fetchData() {
        isLoading = true
        Task {
            let result = await SSHMonitorService.fetchStats(config: config)
            await MainActor.run {
                self.stats = result
                self.isLoading = false
            }
        }
    }
}
