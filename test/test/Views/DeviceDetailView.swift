import SwiftUI

struct DeviceDetailView: View {
    let config: ServerConfig
    @ObservedObject var store: ServerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                basicInfoCard

                if let stats {
                    cpuCard(stats)
                    memoryCard(stats)
                    diskCard(stats)
                    networkCard(stats)

                    if shouldShowOpenWrtCards(for: stats) {
                        connectedDevicesCard(stats)
                        wifiInfoCard(stats)
                    }

                    if !stats.isOnline {
                        detailError(stats)
                    }
                } else {
                    loadingCard
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(config.name)
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

    private var basicInfoCard: some View {
        DetailSectionCard(
            title: "设备信息",
            subtitle: basicInfoSubtitle,
            systemImage: deviceIconName,
            tint: deviceAccentColor
        ) {
            HStack(spacing: 8) {
                DetailPill(
                    text: onlineStatusText,
                    tint: stats?.isOnline == true ? .green : .orange
                )

                DetailPill(
                    text: systemDisplayName,
                    tint: deviceAccentColor
                )

                if shouldShowOpenWrtBadge {
                    DetailPill(
                        text: "OpenWrt",
                        tint: .orange
                    )
                }

                Spacer(minLength: 0)
            }

            DetailRow(label: "设备名称", value: config.name)
            DetailRow(label: "连接地址", value: "\(config.host):\(config.port)")
            DetailRow(label: "登录账户", value: config.username.isEmpty ? "未设置" : config.username)
            DetailRow(label: "主机名", value: resolvedHostname)
            DetailRow(label: "在线时长", value: resolvedUptime)

            if stats == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在获取设备的实时信息...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func cpuCard(_ stats: ServerStats) -> some View {
        DetailSectionCard(
            title: "CPU",
            subtitle: stats.isOnline ? "实时占用与处理器信息" : "设备离线，显示最近一次缓存",
            systemImage: "cpu",
            tint: .green
        ) {
            HStack(spacing: 12) {
                DetailMetricTile(
                    label: "占用率",
                    value: percentText(stats.cpuUsage),
                    systemImage: "speedometer",
                    tint: .green
                )

                if let cpuTemp = stats.cpuTemperatureC {
                    DetailMetricTile(
                        label: "温度",
                        value: cpuTemperatureText(cpuTemp),
                        systemImage: "thermometer",
                        tint: cpuTemperatureColor(for: cpuTemp)
                    )
                }
            }

            DetailRow(label: "型号", value: stats.cpuModel.isEmpty ? "未知" : stats.cpuModel)
            DetailRow(label: "核心数", value: stats.cpuCores > 0 ? "\(stats.cpuCores)" : "未知")
            DetailRow(label: "频率", value: stats.cpuFrequency.isEmpty ? "未知" : stats.cpuFrequency)

            if !stats.nssCores.isEmpty || stats.nssFrequencyMHz != nil {
                Divider()

                Text("NSS")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let frequency = stats.nssFrequencyMHz {
                    DetailRow(label: "频率", value: String(format: "%.0f MHz", frequency))
                }

                ForEach(stats.nssCores.indices, id: \.self) { index in
                    let core = stats.nssCores[index]

                    if index > 0 {
                        Divider()
                    }

                    Text(core.name)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    DetailRow(label: "最小占用", value: percentText(core.minUsage))
                    DetailRow(label: "平均占用", value: percentText(core.avgUsage))
                    DetailRow(label: "峰值占用", value: percentText(core.maxUsage))
                }
            }
        }
    }

    @ViewBuilder
    private func memoryCard(_ stats: ServerStats) -> some View {
        DetailSectionCard(
            title: "内存",
            subtitle: stats.isOnline ? "当前可用与占用情况" : "设备离线，显示最近一次缓存",
            systemImage: "memorychip",
            tint: .blue
        ) {
            HStack(spacing: 12) {
                DetailMetricTile(
                    label: "占用率",
                    value: percentText(stats.memUsage),
                    systemImage: "chart.pie.fill",
                    tint: .blue
                )

                DetailMetricTile(
                    label: "可用内存",
                    value: formattedCapacity(stats.memAvailable),
                    systemImage: "square.stack.3d.up.fill",
                    tint: .teal
                )
            }

            DetailRow(label: "总内存", value: formattedCapacity(stats.memTotal))
            DetailRow(label: "已使用", value: formattedCapacity(max(stats.memTotal - stats.memAvailable, 0)))
            DetailRow(label: "剩余可用", value: formattedCapacity(stats.memAvailable))
        }
    }

    @ViewBuilder
    private func diskCard(_ stats: ServerStats) -> some View {
        if stats.rootDisk != nil || stats.overlayDisk != nil || stats.diskUsage > 0 {
            DetailSectionCard(
                title: "磁盘",
                subtitle: "存储空间与挂载点",
                systemImage: "externaldrive.fill",
                tint: .brown
            ) {
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

    private func networkCard(_ stats: ServerStats) -> some View {
        DetailSectionCard(
            title: "网络",
            subtitle: stats.isOnline ? "当前上下行速率" : "设备离线，显示最近一次缓存",
            systemImage: "antenna.radiowaves.left.and.right",
            tint: .indigo
        ) {
            HStack(spacing: 12) {
                DetailMetricTile(
                    label: "下载",
                    value: stats.isOnline ? stats.downloadSpeed : "--",
                    systemImage: "arrow.down.circle.fill",
                    tint: .blue
                )

                DetailMetricTile(
                    label: "上传",
                    value: stats.isOnline ? stats.uploadSpeed : "--",
                    systemImage: "arrow.up.circle.fill",
                    tint: .indigo
                )
            }

            DetailRow(label: "连接状态", value: onlineStatusText)
            DetailRow(label: "连接地址", value: "\(config.host):\(config.port)")

            if let loadAverage1m = stats.loadAverage1m {
                DetailRow(label: "系统负载 1m", value: String(format: "%.2f", loadAverage1m))
            }
            if let loadAverage5m = stats.loadAverage5m {
                DetailRow(label: "系统负载 5m", value: String(format: "%.2f", loadAverage5m))
            }
            if let loadAverage15m = stats.loadAverage15m {
                DetailRow(label: "系统负载 15m", value: String(format: "%.2f", loadAverage15m))
            }
        }
    }

    @ViewBuilder
    private func connectedDevicesCard(_ stats: ServerStats) -> some View {
        let devices = stats.routerInfo.connectedDevices
        let wiredCount = devices.filter { $0.connectionType == .wired }.count
        let wifi24Count = devices.filter { $0.connectionType == .wifi24 }.count
        let wifi5Count = devices.filter { $0.connectionType == .wifi5 }.count
        let unknownCount = devices.filter { $0.connectionType == .unknown }.count

        DetailSectionCard(
            title: "已连接设备",
            subtitle: "当前共 \(devices.count) 台接入设备",
            systemImage: "dot.radiowaves.left.and.right",
            tint: .orange
        ) {
            HStack(spacing: 8) {
                if wiredCount > 0 {
                    connectionBadge(icon: "cable.connector", label: "有线", count: wiredCount, color: .blue)
                }
                if wifi24Count > 0 {
                    connectionBadge(icon: "wifi", label: "2.4G", count: wifi24Count, color: .green)
                }
                if wifi5Count > 0 {
                    connectionBadge(icon: "wifi", label: "5G", count: wifi5Count, color: .purple)
                }
                if unknownCount > 0 {
                    connectionBadge(icon: "questionmark.circle", label: "未知", count: unknownCount, color: .gray)
                }
                Spacer(minLength: 0)
            }

            if devices.isEmpty {
                Text("当前没有采集到已连接设备。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Divider()

                ForEach(devices) { device in
                    connectedDeviceRow(device)

                    if device.id != devices.last?.id {
                        Divider().padding(.leading, 28)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wifiInfoCard(_ stats: ServerStats) -> some View {
        let sensors = stats.additionalTemperatureSensors
            .filter { sensor in
                let label = sensor.label.lowercased()
                return label.contains("wifi") || label.contains("wlan") || label.contains("radio") || label.contains("phy")
            }

        DetailSectionCard(
            title: "WiFi 信息",
            subtitle: "无线射频与温度信息",
            systemImage: "wifi",
            tint: .orange
        ) {
            HStack(spacing: 12) {
                if let wifi24 = stats.wifi24TemperatureC {
                    DetailMetricTile(
                        label: "2.4G",
                        value: cpuTemperatureText(wifi24),
                        systemImage: "wifi",
                        tint: cpuTemperatureColor(for: wifi24)
                    )
                }

                if let wifi5 = stats.wifi5TemperatureC {
                    DetailMetricTile(
                        label: "5G",
                        value: cpuTemperatureText(wifi5),
                        systemImage: "wifi",
                        tint: cpuTemperatureColor(for: wifi5)
                    )
                }
            }

            if sensors.isEmpty && stats.wifi24TemperatureC == nil && stats.wifi5TemperatureC == nil {
                Text("当前还没有采集到更详细的 WiFi 信息，后面我们可以继续补充更多字段。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(sensors.indices, id: \.self) { index in
                    let sensor = sensors[index]
                    DetailRow(label: sensor.label, value: cpuTemperatureText(sensor.valueC))
                }
            }
        }
    }

    private var loadingCard: some View {
        DetailSectionCard(
            title: "正在加载",
            subtitle: "首次进入详情页时会先拉取一轮实时数据",
            systemImage: "hourglass",
            tint: .gray
        ) {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在准备 CPU、内存、磁盘和网络卡片的数据。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func detailError(_ stats: ServerStats) -> some View {
        DetailSectionCard(
            title: "连接信息",
            subtitle: "本次采集失败时的诊断输出",
            systemImage: "exclamationmark.triangle.fill",
            tint: .red
        ) {
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

    @ViewBuilder
    private func connectionBadge(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)

            Text("\(label) \(count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func connectedDeviceRow(_ device: ConnectedDevice) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: deviceIcon(for: device.connectionType))
                .font(.subheadline)
                .foregroundColor(deviceColor(for: device.connectionType))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !device.ip.isEmpty {
                        Text(device.ip)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(device.mac)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(device.connectionType.displayName)
                    .font(.caption)
                    .foregroundColor(deviceColor(for: device.connectionType))

                if let signal = device.signalDBm {
                    HStack(spacing: 2) {
                        Image(systemName: signalIcon(for: signal))
                            .font(.caption2)
                        Text("\(signal) dBm")
                            .font(.caption)
                    }
                    .foregroundColor(signalColor(for: signal))
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func deviceIcon(for type: ConnectedDeviceConnectionType) -> String {
        switch type {
        case .wired:
            return "cable.connector"
        case .wifi24, .wifi5:
            return "wifi"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func deviceColor(for type: ConnectedDeviceConnectionType) -> Color {
        switch type {
        case .wired:
            return .blue
        case .wifi24:
            return .green
        case .wifi5:
            return .purple
        case .unknown:
            return .gray
        }
    }

    private func signalIcon(for dBm: Int) -> String {
        switch dBm {
        case -50...0:
            return "wifi"
        case -70...(-51):
            return "wifi"
        case -85...(-71):
            return "wifi.exclamationmark"
        default:
            return "wifi.slash"
        }
    }

    private func signalColor(for dBm: Int) -> Color {
        switch dBm {
        case -50...0:
            return .green
        case -70...(-51):
            return .orange
        case -85...(-71):
            return .red
        default:
            return .red
        }
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

    private func cpuTemperatureText(_ value: Double) -> String {
        String(format: "%.1f°C", value)
    }

    private func cpuTemperatureColor(for value: Double) -> Color {
        switch value {
        case ..<55:
            return .green
        case ..<75:
            return .orange
        default:
            return .red
        }
    }

    private func shouldShowOpenWrtCards(for stats: ServerStats) -> Bool {
        stats.routerInfo.isRouter || stats.osName.lowercased().contains("openwrt")
    }

    private var shouldShowOpenWrtBadge: Bool {
        guard let stats else { return false }
        return shouldShowOpenWrtCards(for: stats)
    }

    private var stats: ServerStats? {
        store.stats(for: config)
    }

    private var isRefreshing: Bool {
        store.isRefreshing(config.id)
    }

    private var basicInfoSubtitle: String {
        if let stats {
            return stats.isOnline ? "设备在线，可查看实时运行状态" : "设备当前离线，显示最近一次缓存"
        }
        return isRefreshing ? "正在拉取设备状态..." : "等待设备首次上报状态"
    }

    private var onlineStatusText: String {
        guard let stats else { return "加载中" }
        return stats.isOnline ? "在线" : "离线"
    }

    private var resolvedHostname: String {
        guard let stats else { return "正在获取" }
        return stats.hostname.isEmpty ? "未知" : stats.hostname
    }

    private var resolvedUptime: String {
        guard let stats else { return "正在获取" }
        return stats.uptime.isEmpty ? "--" : stats.uptime
    }

    private var systemDisplayName: String {
        guard let stats else { return "系统识别中" }

        let osName = stats.osName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !osName.isEmpty else {
            return stats.routerInfo.isRouter ? "路由设备" : "未知系统"
        }

        let lowercased = osName.lowercased()

        if lowercased.contains("openwrt") {
            return "OpenWrt"
        }
        if lowercased.contains("ubuntu") {
            return "Ubuntu"
        }
        if lowercased.contains("debian") {
            return "Debian"
        }
        if lowercased.contains("centos") {
            return "CentOS"
        }
        if lowercased.contains("fedora") {
            return "Fedora"
        }
        if lowercased.contains("arch") {
            return "Arch Linux"
        }
        if lowercased.contains("macos") || lowercased.contains("darwin") {
            return "macOS"
        }
        if lowercased.contains("raspbian") {
            return "Raspbian"
        }
        if lowercased.contains("linux") {
            return "Linux"
        }

        return osName
    }

    private var deviceIconName: String {
        if stats?.routerInfo.isRouter == true {
            return "wifi.router"
        }
        return "server.rack"
    }

    private var deviceAccentColor: Color {
        stats?.routerInfo.isRouter == true ? .orange : .blue
    }
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.black.opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.primary)
        }
        .font(.subheadline)
    }
}

private struct DetailPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.10))
            .clipShape(Capsule())
    }
}

private struct DetailMetricTile: View {
    let label: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundColor(tint)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }
}
