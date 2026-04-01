import SwiftUI

struct DeviceDetailView: View {
    let config: ServerConfig
    @ObservedObject var store: ServerStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(config.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("\(config.username)@\(config.host):\(config.port)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let stats {
                    systemCard(stats)
                    cpuCard(stats)
                    temperatureCard(stats)
                    nssCard(stats)
                    memoryCard(stats)
                    diskCard(stats)
                    
                    if !stats.isOnline {
                        detailError(stats)
                    }
                } else if isRefreshing {
                    HStack {
                        Spacer()
                        ProgressView("加载状态中...")
                        Spacer()
                    }
                    .padding(.top, 40)
                }
            }
            .padding(16)
        }
        .navigationTitle("设备详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.refreshServer(config, forceDynamic: true, forceStatic: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isRefreshing)
            }
        }
        .task(id: config.id) {
            await store.refreshServer(config, forceDynamic: true)

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await store.refreshServer(config, forceDynamic: true)
            }
        }
    }
    
    @ViewBuilder
    private func systemCard(_ stats: ServerStats) -> some View {
        DetailSectionCard(title: "系统信息") {
            DetailRow(label: "系统", value: stats.osName.isEmpty ? "unknown" : stats.osName)
            DetailRow(label: "主机名", value: stats.hostname.isEmpty ? "unknown" : stats.hostname)
            DetailRow(label: "在线状态", value: stats.isOnline ? "online" : "offline")
        }
    }
    
    @ViewBuilder
    private func cpuCard(_ stats: ServerStats) -> some View {
        DetailSectionCard(title: "CPU") {
            DetailRow(label: "型号", value: stats.cpuModel.isEmpty ? "unknown" : stats.cpuModel)
            DetailRow(label: "核心数", value: "\(stats.cpuCores)")
            DetailRow(label: "占用率", value: percentText(stats.cpuUsage))
            DetailRow(label: "频率", value: stats.cpuFrequency.isEmpty ? "unknown" : stats.cpuFrequency)
        }
    }

    @ViewBuilder
    private func temperatureCard(_ stats: ServerStats) -> some View {
        let hasWiFiTemps = stats.wifi24TemperatureC != nil || stats.wifi5TemperatureC != nil
        let hasAdditionalTemps = !stats.additionalTemperatureSensors.isEmpty
        let shouldShow = stats.cpuTemperatureC != nil || hasWiFiTemps || hasAdditionalTemps

        if shouldShow {
            DetailSectionCard(title: "温度") {
                if let cpuTemp = stats.cpuTemperatureC {
                    DetailRow(label: "CPU", value: cpuTemperatureText(cpuTemp))
                }

                if let wifi24 = stats.wifi24TemperatureC {
                    DetailRow(label: "WiFi 2.4G", value: cpuTemperatureText(wifi24))
                }
                if let wifi5 = stats.wifi5TemperatureC {
                    DetailRow(label: "WiFi 5G", value: cpuTemperatureText(wifi5))
                }


            }
        }
    }
    
    @ViewBuilder
    private func memoryCard(_ stats: ServerStats) -> some View {
        DetailSectionCard(title: "内存") {
            DetailRow(label: "总内存", value: "\(stats.memTotal) MB")
            DetailRow(label: "可用内存", value: "\(stats.memAvailable) MB")
            DetailRow(label: "占用率", value: percentText(stats.memUsage))
        }
    }

    @ViewBuilder
    private func diskCard(_ stats: ServerStats) -> some View {
        if stats.rootDisk != nil || stats.overlayDisk != nil || stats.diskUsage > 0 {
            DetailSectionCard(title: "磁盘") {
                if let rootDisk = stats.rootDisk {
                    diskGroup(rootDisk, title: "/")
                } else if stats.diskUsage > 0 {
                    fallbackDiskGroup
                }

                if stats.rootDisk != nil && stats.overlayDisk != nil {
                    Divider()
                }

                if let overlayDisk = stats.overlayDisk {
                    diskGroup(overlayDisk, title: "/overlay")
                }
            }
        }
    }

    @ViewBuilder
    private func nssCard(_ stats: ServerStats) -> some View {
        if !stats.nssCores.isEmpty || stats.nssFrequencyMHz != nil {
            DetailSectionCard(title: "NSS") {
                if let frequency = stats.nssFrequencyMHz {
                    DetailRow(label: "频率", value: String(format: "%.0f MHz", frequency))
                }

                ForEach(stats.nssCores.indices, id: \.self) { index in
                    let core = stats.nssCores[index]
                    if index > 0 || stats.nssFrequencyMHz != nil {
                        Divider()
                    }
                    Text(core.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    DetailRow(label: "最小占用", value: percentText(core.minUsage))
                    DetailRow(label: "平均占用", value: percentText(core.avgUsage))
                    DetailRow(label: "峰值占用", value: percentText(core.maxUsage))
                }
            }
        }
    }
    
    @ViewBuilder
    private func detailError(_ stats: ServerStats) -> some View {
        DetailSectionCard(title: "连接信息") {
            Text(stats.statusMessage.isEmpty ? "连接失败" : stats.statusMessage)
                .font(.subheadline)
                .foregroundColor(.primary)
            ForEach(stats.diagnostics, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            if !stats.rawOutput.isEmpty {
                Text(stats.rawOutput)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
    
    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    private func formattedCapacity(_ megabytes: Int) -> String {
        let gigabytes = Double(megabytes) / 1024
        if gigabytes >= 1024 {
            return String(format: "%.2f TB", gigabytes / 1024)
        }
        if gigabytes >= 1 {
            return String(format: "%.1f GB", gigabytes)
        }
        return "\(megabytes) MB"
    }

    private func cpuTemperatureText(_ value: Double?) -> String {
        guard let value else { return "unknown" }
        return String(format: "%.1f°C", value)
    }

    private func cpuTemperatureText(_ value: Double) -> String {
        String(format: "%.1f°C", value)
    }

    private var stats: ServerStats? {
        store.stats(for: config)
    }

    private var isRefreshing: Bool {
        store.isRefreshing(config.id)
    }

    @ViewBuilder
    private func diskGroup(_ disk: ServerDiskInfo, title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
        DetailRow(label: "挂载点", value: disk.mountPoint)
        DetailRow(label: "总空间", value: formattedCapacity(disk.totalMB))
        DetailRow(label: "已用", value: formattedCapacity(disk.usedMB))
        DetailRow(label: "可用", value: formattedCapacity(disk.availableMB))
        DetailRow(label: "占用率", value: percentText(disk.usage))
    }

    private var fallbackDiskGroup: some View {
        Group {
            Text("/")
                .font(.subheadline)
                .fontWeight(.semibold)
            DetailRow(label: "挂载点", value: "/")
            DetailRow(label: "占用率", value: percentText(stats?.diskUsage ?? 0))
        }
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}