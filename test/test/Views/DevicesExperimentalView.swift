import SwiftUI

struct DevicesExperimentalView: View {
    @ObservedObject var store: ServerStore
    @State private var selectedServer: ServerConfig?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if store.servers.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.servers) { server in
                            ExperimentalServerCard(
                                config: server,
                                stats: store.stats(for: server)
                            ) {
                                selectedServer = server
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(ExperimentalHomePalette.pageBackground.ignoresSafeArea())
            .navigationTitle("概览")
            .task(id: store.servers.map(\.id)) {
                await store.refreshAllIfNeeded()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await store.refreshAllIfNeeded(forceDynamic: true)
                }
            }
            .navigationDestination(item: $selectedServer) { config in
                DeviceDetailView(config: config, store: store)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("还没有服务器")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(ExperimentalHomePalette.primaryText)

            Text("先去设置里添加服务器。经典版首屏已经保留好，这里我们可以放心实验新的概览风格。")
                .font(.subheadline)
                .foregroundColor(ExperimentalHomePalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ExperimentalHomePalette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(ExperimentalHomePalette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct ExperimentalServerCard: View {
    let config: ServerConfig
    let stats: ServerStats?
    let onOpenDetail: () -> Void

    private var isOnline: Bool {
        stats?.isOnline == true
    }

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 20) {
                header
                cpuAndMemorySection
                divider
                temperatureSection
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ExperimentalHomePalette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(ExperimentalHomePalette.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(config.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(ExperimentalHomePalette.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(ExperimentalHomePalette.secondaryText.opacity(0.7))
                        .frame(width: 5, height: 5)
                    Text(shortOSName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(ExperimentalHomePalette.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(isOnline ? ExperimentalHomePalette.online : ExperimentalHomePalette.offline)
                    .frame(width: 8, height: 8)

                Text(isOnline ? "运行中" : "离线")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(isOnline ? ExperimentalHomePalette.online : ExperimentalHomePalette.offline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill((isOnline ? ExperimentalHomePalette.online : ExperimentalHomePalette.offline).opacity(0.12))
            )
        }
    }

    private var cpuAndMemorySection: some View {
        VStack(spacing: 14) {
            ExperimentalSparkMetricRow(
                label: "CPU",
                value: stats?.cpuUsage,
                percentageText: percentageText(stats?.cpuUsage),
                color: ExperimentalHomePalette.cpuSpark,
                seed: dynamicSeed(offset: 0.37)
            )

            ExperimentalSparkMetricRow(
                label: "MEM",
                value: stats?.memUsage,
                percentageText: percentageText(stats?.memUsage),
                color: ExperimentalHomePalette.memorySpark,
                seed: dynamicSeed(offset: 1.71)
            )
        }
    }

    private var temperatureSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ExperimentalHomePalette.online.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: "thermometer.medium")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(ExperimentalHomePalette.online)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("CPU 温度")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(ExperimentalHomePalette.sectionLabel)

                Text(temperatureText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(ExperimentalHomePalette.online)
                    .monospacedDigit()
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(ExperimentalHomePalette.divider)
            .frame(height: 1)
    }

    private var shortOSName: String {
        let osName = (stats?.osName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !osName.isEmpty else {
            return "--"
        }

        let lowercased = osName.lowercased()
        if lowercased.contains("debian") { return "Debian" }
        if lowercased.contains("ubuntu") { return "Ubuntu" }
        if lowercased.contains("openwrt") { return "OpenWrt" }
        if lowercased.contains("immortalwrt") { return "ImmortalWrt" }
        if lowercased.contains("centos") { return "CentOS" }
        if lowercased.contains("fedora") { return "Fedora" }
        if lowercased.contains("arch") { return "Arch Linux" }
        if lowercased.contains("linux") { return "Linux" }
        return osName
    }

    private func percentageText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private var temperatureText: String {
        guard let temp = stats?.cpuTemperatureC else {
            return "--"
        }
        return "\(Int(temp.rounded()))°C"
    }

    private func dynamicSeed(offset: Double) -> Double {
        let components = config.id.uuidString.unicodeScalars.map { Double($0.value) }
        let base = components.reduce(0, +) / Double(max(components.count, 1))
        return base * 0.013 + offset
    }
}

private struct ExperimentalSparkMetricRow: View {
    let label: String
    let value: Double?
    let percentageText: String
    let color: Color
    let seed: Double

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(ExperimentalHomePalette.sectionLabel)
                .frame(width: 40, alignment: .leading)

            ExperimentalLiveSparkBars(
                value: value,
                tint: color,
                seed: seed
            )
            .frame(maxWidth: .infinity)

            Text(percentageText)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(ExperimentalHomePalette.primaryText)
                .monospacedDigit()
                .frame(width: 54, alignment: .trailing)
        }
    }
}

private struct ExperimentalLiveSparkBars: View {
    let value: Double?
    let tint: Color
    let seed: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.33, paused: false)) { context in
            GeometryReader { geometry in
                let bars = sparkValues(for: context.date)
                let itemCount = max(bars.count, 1)
                let spacing: CGFloat = 4
                let totalSpacing = spacing * CGFloat(max(itemCount - 1, 0))
                let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(itemCount), 3)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, rawValue in
                        let safeValue = min(max(rawValue, 0), 1)
                        let barHeight = max(CGFloat(safeValue), 0.18) * geometry.size.height

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(tint.gradient)
                            .frame(width: barWidth, height: barHeight)
                            .opacity(value == nil ? 0.35 : 1)
                    }
                }
                .animation(.easeInOut(duration: 0.28), value: bars)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(height: 34)
        }
    }

    private func sparkValues(for date: Date) -> [Double] {
        let baseline = min(max(value ?? 0, 0), 1)
        let amplitude = value == nil ? 0.05 : 0.07 + baseline * 0.16
        let speed = 0.85 + baseline * 1.5
        let time = date.timeIntervalSinceReferenceDate * speed + seed
        let count = 36

        return (0..<count).map { index in
            let x = Double(index)
            let waveA = sin(time * 1.9 + x * 0.33 + seed * 1.7)
            let waveB = cos(time * 1.2 + x * 0.19 + seed * 2.4)
            let waveC = sin(time * 2.7 + x * 0.11 + seed * 0.8)
            let blended = (waveA * 0.52) + (waveB * 0.33) + (waveC * 0.15)
            let value = baseline + blended * amplitude
            return min(max(value, 0.04), 1)
        }
    }
}

private enum ExperimentalHomePalette {
    static let pageBackground = LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.07, blue: 0.10),
            Color(red: 0.05, green: 0.05, blue: 0.08)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardBackground = Color(red: 0.09, green: 0.09, blue: 0.12)
    static let subcardBackground = Color(red: 0.12, green: 0.12, blue: 0.15)
    static let cardBorder = Color.white.opacity(0.07)
    static let divider = Color.white.opacity(0.06)
    static let primaryText = Color(red: 0.96, green: 0.96, blue: 0.99)
    static let secondaryText = Color(red: 0.46, green: 0.47, blue: 0.67)
    static let sectionLabel = Color(red: 0.42, green: 0.43, blue: 0.64)
    static let online = Color(red: 0.23, green: 0.92, blue: 0.56)
    static let offline = Color(red: 0.98, green: 0.74, blue: 0.22)
    static let cpuSpark = Color(red: 0.23, green: 0.49, blue: 0.85)
    static let memorySpark = Color(red: 0.49, green: 0.31, blue: 0.90)
}
