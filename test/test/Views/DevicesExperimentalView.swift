import SwiftUI

struct DevicesExperimentalView: View {
    @ObservedObject var store: ServerStore
    @State private var selectedServer: ServerConfig?
    @State private var metricHistoryByServerID: [UUID: ExperimentalMetricHistory] = [:]

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
                                stats: store.stats(for: server),
                                history: metricHistoryByServerID[server.id]
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
                await MainActor.run {
                    recordCurrentSamples()
                }

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await store.refreshAllIfNeeded(forceDynamic: true)
                    await MainActor.run {
                        recordCurrentSamples()
                    }
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

    @MainActor
    private func recordCurrentSamples() {
        let validIDs = Set(store.servers.map(\.id))
        metricHistoryByServerID = metricHistoryByServerID.filter { validIDs.contains($0.key) }

        for server in store.servers {
            guard let stats = store.stats(for: server) else { continue }

            let sample = ExperimentalMetricSample(
                cpuUsage: stats.isOnline ? stats.cpuUsage : 0,
                memoryUsage: stats.isOnline ? stats.memUsage : 0,
                cpuPSI: stats.pressure.cpuSomeAvg10 ?? 0,
                memoryPSI: max(stats.pressure.memoryFullAvg10 ?? 0, stats.pressure.memorySomeAvg10 ?? 0),
                ioPSI: max(stats.pressure.ioFullAvg10 ?? 0, stats.pressure.ioSomeAvg10 ?? 0)
            )

            var history = metricHistoryByServerID[server.id] ?? ExperimentalMetricHistory(seed: sample)
            history.append(sample)
            metricHistoryByServerID[server.id] = history
        }
    }
}

private struct ExperimentalServerCard: View {
    let config: ServerConfig
    let stats: ServerStats?
    let history: ExperimentalMetricHistory?
    let onOpenDetail: () -> Void

    private var currentHistory: ExperimentalMetricHistory {
        if let history {
            return history
        }

        let fallback = ExperimentalMetricSample(
            cpuUsage: stats?.cpuUsage ?? 0,
            memoryUsage: stats?.memUsage ?? 0,
            cpuPSI: stats?.pressure.cpuSomeAvg10 ?? 0,
            memoryPSI: max(stats?.pressure.memoryFullAvg10 ?? 0, stats?.pressure.memorySomeAvg10 ?? 0),
            ioPSI: max(stats?.pressure.ioFullAvg10 ?? 0, stats?.pressure.ioSomeAvg10 ?? 0)
        )
        return ExperimentalMetricHistory(seed: fallback)
    }

    private var isOnline: Bool {
        stats?.isOnline == true
    }

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 18) {
                header
                cpuAndMemorySection
                divider
                psiSection
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
                values: currentHistory.cpuUsage,
                percentageText: percentageText(stats?.cpuUsage),
                color: ExperimentalHomePalette.cpuSpark
            )

            ExperimentalSparkMetricRow(
                label: "MEM",
                values: currentHistory.memoryUsage,
                percentageText: percentageText(stats?.memUsage),
                color: ExperimentalHomePalette.memorySpark
            )
        }
    }

    private var psiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PSI 压力指数")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(ExperimentalHomePalette.sectionLabel)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                spacing: 12
            ) {
                ExperimentalPSICard(
                    title: "CPU PSI",
                    value: stats?.pressure.cpuSomeAvg10,
                    values: currentHistory.cpuPSI,
                    tint: psiTint(for: stats?.pressure.cpuSomeAvg10)
                )

                ExperimentalPSICard(
                    title: "MEM PSI",
                    value: max(stats?.pressure.memoryFullAvg10 ?? 0, stats?.pressure.memorySomeAvg10 ?? 0),
                    values: currentHistory.memoryPSI,
                    tint: psiTint(for: max(stats?.pressure.memoryFullAvg10 ?? 0, stats?.pressure.memorySomeAvg10 ?? 0))
                )

                ExperimentalPSICard(
                    title: "IO PSI",
                    value: max(stats?.pressure.ioFullAvg10 ?? 0, stats?.pressure.ioSomeAvg10 ?? 0),
                    values: currentHistory.ioPSI,
                    tint: psiTint(for: max(stats?.pressure.ioFullAvg10 ?? 0, stats?.pressure.ioSomeAvg10 ?? 0))
                )
            }
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

    private func psiTint(for value: Double?) -> Color {
        let safeValue = value ?? 0
        if safeValue >= 5 {
            return ExperimentalHomePalette.psiHigh
        }
        if safeValue >= 2 {
            return ExperimentalHomePalette.psiMedium
        }
        return ExperimentalHomePalette.psiLow
    }
}

private struct ExperimentalSparkMetricRow: View {
    let label: String
    let values: [Double]
    let percentageText: String
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundColor(ExperimentalHomePalette.sectionLabel)
                .frame(width: 40, alignment: .leading)

            ExperimentalSparkBars(
                values: values,
                tint: color,
                minimumHeightRatio: 0.18
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

private struct ExperimentalPSICard: View {
    let title: String
    let value: Double?
    let values: [Double]
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(ExperimentalHomePalette.sectionLabel)

            Text(formattedValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(tint)
                .monospacedDigit()

            Spacer(minLength: 0)

            ExperimentalSparkBars(
                values: normalizedPSIValues,
                tintProvider: { psiColor(for: $0) },
                minimumHeightRatio: 0.10,
                cornerRadius: 2,
                height: 22
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .leading)
        .background(ExperimentalHomePalette.subcardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var formattedValue: String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value)
    }

    private var normalizedPSIValues: [Double] {
        values.map { sample in
            let normalized = min(max(sample / 8.0, 0), 1)
            return max(normalized, sample > 0 ? 0.08 : 0)
        }
    }

    private func psiColor(for normalizedValue: Double) -> Color {
        if normalizedValue >= 0.65 {
            return ExperimentalHomePalette.psiHigh
        }
        if normalizedValue >= 0.28 {
            return ExperimentalHomePalette.psiMedium
        }
        return ExperimentalHomePalette.psiLow
    }
}

private struct ExperimentalSparkBars: View {
    let values: [Double]
    var tint: Color? = nil
    var tintProvider: ((Double) -> Color)? = nil
    var minimumHeightRatio: Double = 0.12
    var cornerRadius: CGFloat = 3
    var height: CGFloat = 34

    var body: some View {
        GeometryReader { geometry in
            let itemCount = max(values.count, 1)
            let spacing: CGFloat = 4
            let totalSpacing = spacing * CGFloat(max(itemCount - 1, 0))
            let barWidth = max((geometry.size.width - totalSpacing) / CGFloat(itemCount), 3)

            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, rawValue in
                    let safeValue = min(max(rawValue, 0), 1)
                    let height = max(CGFloat(safeValue), CGFloat(minimumHeightRatio)) * geometry.size.height

                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill((tintProvider?(safeValue) ?? tint ?? ExperimentalHomePalette.cpuSpark).gradient)
                        .frame(width: barWidth, height: height)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: height)
    }
}

private struct ExperimentalMetricSample {
    let cpuUsage: Double
    let memoryUsage: Double
    let cpuPSI: Double
    let memoryPSI: Double
    let ioPSI: Double
}

private struct ExperimentalMetricHistory {
    var cpuUsage: [Double]
    var memoryUsage: [Double]
    var cpuPSI: [Double]
    var memoryPSI: [Double]
    var ioPSI: [Double]

    private static let maxSamples = 36

    init(seed sample: ExperimentalMetricSample) {
        cpuUsage = Array(repeating: min(max(sample.cpuUsage, 0), 1), count: Self.maxSamples)
        memoryUsage = Array(repeating: min(max(sample.memoryUsage, 0), 1), count: Self.maxSamples)
        cpuPSI = Array(repeating: max(sample.cpuPSI, 0), count: Self.maxSamples)
        memoryPSI = Array(repeating: max(sample.memoryPSI, 0), count: Self.maxSamples)
        ioPSI = Array(repeating: max(sample.ioPSI, 0), count: Self.maxSamples)
    }

    mutating func append(_ sample: ExperimentalMetricSample) {
        cpuUsage = appended(cpuUsage, value: min(max(sample.cpuUsage, 0), 1))
        memoryUsage = appended(memoryUsage, value: min(max(sample.memoryUsage, 0), 1))
        cpuPSI = appended(cpuPSI, value: max(sample.cpuPSI, 0))
        memoryPSI = appended(memoryPSI, value: max(sample.memoryPSI, 0))
        ioPSI = appended(ioPSI, value: max(sample.ioPSI, 0))
    }

    private func appended(_ values: [Double], value: Double) -> [Double] {
        var next = values
        next.append(value)
        if next.count > Self.maxSamples {
            next.removeFirst(next.count - Self.maxSamples)
        }
        return next
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
    static let psiLow = Color(red: 0.23, green: 0.92, blue: 0.56)
    static let psiMedium = Color(red: 1.00, green: 0.69, blue: 0.10)
    static let psiHigh = Color(red: 0.88, green: 0.27, blue: 0.30)
}
