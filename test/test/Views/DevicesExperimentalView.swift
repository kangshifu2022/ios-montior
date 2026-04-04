import SwiftUI

struct DevicesExperimentalView: View {
    @ObservedObject var store: ServerStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ExperimentalHomeTheme.storageKey) private var experimentalHomeThemeRawValue = ExperimentalHomeTheme.system.rawValue
    @State private var selectedServer: ServerConfig?

    private var selectedTheme: ExperimentalHomeTheme {
        ExperimentalHomeTheme(rawValue: experimentalHomeThemeRawValue) ?? .system
    }

    private var resolvedColorScheme: ColorScheme {
        switch selectedTheme {
        case .system:
            return colorScheme
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch selectedTheme {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    private var palette: ExperimentalHomePalette {
        ExperimentalHomePalette.palette(for: resolvedColorScheme)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ExperimentalOverviewHero(store: store, palette: palette)

                    if store.servers.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 18) {
                            ForEach(store.servers) { server in
                                ExperimentalServerCard(
                                    config: server,
                                    stats: store.stats(for: server),
                                    palette: palette
                                ) {
                                    selectedServer = server
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .background(palette.pageBackground.ignoresSafeArea())
            .navigationTitle("概览")
            .navigationDestination(item: $selectedServer) { config in
                DeviceDetailView(config: config, store: store)
            }
            .task(id: store.servers.map(\.id)) {
                await store.refreshAllIfNeeded()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await store.refreshAllIfNeeded(forceDynamic: true)
                }
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("还没有服务器")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryText)

            Text("实验版首屏已经切到点阵方案。先去设置里添加服务器，我们再继续打磨卡片气质。")
                .font(.subheadline)
                .foregroundColor(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: palette.cardShadow, radius: 18, x: 0, y: 10)
    }
}

private struct ExperimentalOverviewHero: View {
    @ObservedObject var store: ServerStore
    let palette: ExperimentalHomePalette

    private var totalCount: Int {
        store.servers.count
    }

    private var onlineCount: Int {
        store.servers.filter { store.stats(for: $0)?.isOnline == true }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("10 x 10 Dot Matrix")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(palette.primaryText)

                Text("点阵区域继续保持紧凑，但内部恢复到 10 x 10 小圆点。这样在不明显增加卡片高度的前提下，读数会更细一点。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits {
                HStack(spacing: 10) {
                    ExperimentalSummaryPill(
                        title: "在线",
                        value: "\(onlineCount)/\(totalCount)",
                        tint: palette.online,
                        palette: palette
                    )

                    ExperimentalSummaryPill(
                        title: "轮询",
                        value: "约 3 秒",
                        tint: palette.cpuAccent,
                        palette: palette
                    )

                    ExperimentalSummaryPill(
                        title: "矩阵",
                        value: "10 x 10",
                        tint: palette.memoryAccent,
                        palette: palette
                    )
                }

                VStack(spacing: 10) {
                    ExperimentalSummaryPill(
                        title: "在线",
                        value: "\(onlineCount)/\(totalCount)",
                        tint: palette.online,
                        palette: palette
                    )

                    ExperimentalSummaryPill(
                        title: "轮询",
                        value: "约 3 秒",
                        tint: palette.cpuAccent,
                        palette: palette
                    )

                    ExperimentalSummaryPill(
                        title: "矩阵",
                        value: "10 x 10",
                        tint: palette.memoryAccent,
                        palette: palette
                    )
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.heroBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: palette.cardShadow, radius: 20, x: 0, y: 10)
    }
}

private struct ExperimentalSummaryPill: View {
    let title: String
    let value: String
    let tint: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(palette.secondaryText)

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(palette.isDark ? 0.10 : 0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(palette.isDark ? 0.18 : 0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ExperimentalServerCard: View {
    let config: ServerConfig
    let stats: ServerStats?
    let palette: ExperimentalHomePalette
    let onOpenDetail: () -> Void

    private var isOnline: Bool {
        stats?.isOnline == true
    }

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 14) {
                header

                HStack(alignment: .top, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        ExperimentalMetricTile(
                            label: "CPU",
                            percentage: percentageValue(stats?.cpuUsage),
                            tint: palette.cpuAccent,
                            palette: palette
                        )

                        ExperimentalMetricTile(
                            label: "MEM",
                            percentage: percentageValue(stats?.memUsage),
                            tint: palette.memoryAccent,
                            palette: palette
                        )
                    }

                    ExperimentalDetailPanel(
                        items: detailItems,
                        palette: palette
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(palette.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: palette.cardShadow, radius: 20, x: 0, y: 10)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(config.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Circle()
                        .fill(palette.secondaryText.opacity(0.75))
                        .frame(width: 5, height: 5)

                    Text(shortOSName)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(isOnline ? palette.online : palette.offline)
                    .frame(width: 8, height: 8)

                Text(isOnline ? "运行中" : "离线")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(isOnline ? palette.online : palette.offline)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill((isOnline ? palette.online : palette.offline).opacity(palette.isDark ? 0.12 : 0.10))
            )
        }
    }

    private var detailItems: [ExperimentalDetailItem] {
        var items: [ExperimentalDetailItem] = []

        if let temperatureText {
            items.append(ExperimentalDetailItem(label: "CPU 温度", value: temperatureText, tint: palette.online))
        }

        if let wifi24 = wifi24TemperatureText {
            items.append(ExperimentalDetailItem(label: "WiFi 2.4G", value: wifi24, tint: palette.memoryAccent))
        }

        if let wifi5 = wifi5TemperatureText {
            items.append(ExperimentalDetailItem(label: "WiFi 5G", value: wifi5, tint: palette.cpuAccent))
        }

        items.append(ExperimentalDetailItem(label: "在线时长", value: uptimeText, tint: palette.metaTint))
        items.append(ExperimentalDetailItem(label: "主机", value: config.host, tint: palette.metaTint))

        return Array(items.prefix(4))
    }

    private var shortOSName: String {
        let osName = (stats?.osName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !osName.isEmpty else {
            return "--"
        }

        let lowercased = osName.lowercased()
        if lowercased.contains("immortalwrt") { return "ImmortalWrt" }
        if lowercased.contains("openwrt") { return "OpenWrt" }
        if lowercased.contains("debian") { return "Debian" }
        if lowercased.contains("ubuntu") { return "Ubuntu" }
        if lowercased.contains("centos") { return "CentOS" }
        if lowercased.contains("fedora") { return "Fedora" }
        if lowercased.contains("arch") { return "Arch Linux" }
        if lowercased.contains("linux") { return "Linux" }
        return osName
    }

    private var temperatureText: String? {
        guard let temp = stats?.cpuTemperatureC else {
            return nil
        }
        return "\(Int(temp.rounded()))°C"
    }

    private var wifi24TemperatureText: String? {
        guard let temp = stats?.wifi24TemperatureC else {
            return nil
        }
        return "\(Int(temp.rounded()))°C"
    }

    private var wifi5TemperatureText: String? {
        guard let temp = stats?.wifi5TemperatureC else {
            return nil
        }
        return "\(Int(temp.rounded()))°C"
    }

    private var uptimeText: String {
        let uptime = (stats?.uptime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return uptime.isEmpty ? "--" : uptime
    }

    private func percentageValue(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }
}

private struct ExperimentalDetailItem: Identifiable {
    let label: String
    let value: String
    let tint: Color

    var id: String { label }
}

private struct ExperimentalDetailPanel: View {
    let items: [ExperimentalDetailItem]
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(item.tint)
                        .frame(width: 5, height: 5)

                    Text(item.label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.secondaryText)
                        .frame(width: 56, alignment: .leading)

                    Text(item.value)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(palette.subcardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct ExperimentalMetricTile: View {
    let label: String
    let percentage: Int?
    let tint: Color
    let palette: ExperimentalHomePalette

    private var percentageText: String {
        guard let percentage else { return "--" }
        return "\(percentage)%"
    }

    private var compactLabelText: String {
        "\(label) \(percentageText)"
    }

    var body: some View {
        VStack(spacing: 8) {
            ExperimentalDotMatrix(
                percentage: percentage,
                tint: tint,
                palette: palette
            )
            .frame(width: 42, height: 42)

            Text(compactLabelText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .fixedSize()
        .opacity(percentage == nil ? 0.78 : 1)
    }
}

private struct ExperimentalDotMatrix: View {
    let percentage: Int?
    let tint: Color
    let palette: ExperimentalHomePalette

    private let size = 10

    private var activeCount: Int {
        let total = size * size
        let normalized = Double(min(max(percentage ?? 0, 0), 100)) / 100
        return Int((normalized * Double(total)).rounded())
    }

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let spacing: CGFloat = side < 46 ? 1.2 : 1.5
            let tile = max((side - (spacing * CGFloat(size - 1))) / CGFloat(size), 1.8)

            VStack(spacing: spacing) {
                ForEach(0..<size, id: \.self) { visualRow in
                    HStack(spacing: spacing) {
                        ForEach(0..<size, id: \.self) { column in
                            let logicalRow = (size - 1) - visualRow
                            let index = (logicalRow * size) + column
                            let isActive = index < activeCount
                            let frontier = max(activeCount - 1, 0)
                            let distance = abs(index - frontier)
                            let glow = isActive ? max(0, 1 - (Double(distance) / 8)) : 0

                            Circle()
                                .fill(fillColor(isActive: isActive, glow: glow))
                                .overlay(
                                    Circle()
                                        .stroke(borderColor(isActive: isActive, glow: glow), lineWidth: 0.3)
                                )
                                .frame(width: tile, height: tile)
                                .scaleEffect(isActive ? (0.9 + (glow * 0.05)) : 0.74)
                                .shadow(
                                    color: isActive ? tint.opacity((palette.isDark ? 0.07 : 0.04) + (glow * 0.06)) : .clear,
                                    radius: isActive ? (0.8 + (glow * 1.1)) : 0
                                )
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: activeCount)
    }

    private func fillColor(isActive: Bool, glow: Double) -> Color {
        if isActive {
            return tint.opacity((palette.isDark ? 0.62 : 0.56) + (glow * 0.22))
        }
        return palette.matrixInactive
    }

    private func borderColor(isActive: Bool, glow: Double) -> Color {
        if isActive {
            return palette.activeMatrixBorder.opacity((palette.isDark ? 0.08 : 0.12) + (glow * 0.08))
        }
        return palette.inactiveMatrixBorder
    }
}

private struct ExperimentalHomePalette {
    let isDark: Bool
    let themeName: String
    let pageBackground: LinearGradient
    let heroBackground: LinearGradient
    let cardBackground: Color
    let subcardBackground: Color
    let cardBorder: Color
    let matrixInactive: Color
    let inactiveMatrixBorder: Color
    let activeMatrixBorder: Color
    let primaryText: Color
    let secondaryText: Color
    let online: Color
    let offline: Color
    let cpuAccent: Color
    let memoryAccent: Color
    let metaTint: Color
    let cardShadow: Color

    static func palette(for colorScheme: ColorScheme) -> ExperimentalHomePalette {
        switch colorScheme {
        case .dark:
            return ExperimentalHomePalette(
                isDark: true,
                themeName: "深色",
                pageBackground: LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.07, blue: 0.09),
                        Color(red: 0.04, green: 0.05, blue: 0.07)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                heroBackground: LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.17),
                        Color(red: 0.08, green: 0.09, blue: 0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                cardBackground: Color(red: 0.09, green: 0.10, blue: 0.13),
                subcardBackground: Color(red: 0.12, green: 0.13, blue: 0.17),
                cardBorder: Color.white.opacity(0.07),
                matrixInactive: Color.white.opacity(0.055),
                inactiveMatrixBorder: Color.white.opacity(0.02),
                activeMatrixBorder: Color.white,
                primaryText: Color(red: 0.95, green: 0.96, blue: 0.99),
                secondaryText: Color(red: 0.49, green: 0.52, blue: 0.66),
                online: Color(red: 0.22, green: 0.86, blue: 0.53),
                offline: Color(red: 0.98, green: 0.73, blue: 0.24),
                cpuAccent: Color(red: 0.98, green: 0.36, blue: 0.39),
                memoryAccent: Color(red: 0.22, green: 0.81, blue: 0.50),
                metaTint: Color(red: 0.35, green: 0.53, blue: 0.93),
                cardShadow: Color.black.opacity(0.22)
            )
        case .light:
            return ExperimentalHomePalette(
                isDark: false,
                themeName: "浅色",
                pageBackground: LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.97, blue: 1.00),
                        Color(red: 0.92, green: 0.94, blue: 0.98)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                heroBackground: LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.995, blue: 1.0),
                        Color(red: 0.94, green: 0.96, blue: 0.99)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                cardBackground: Color.white.opacity(0.95),
                subcardBackground: Color(red: 0.96, green: 0.97, blue: 0.995),
                cardBorder: Color(red: 0.11, green: 0.15, blue: 0.24).opacity(0.08),
                matrixInactive: Color(red: 0.18, green: 0.23, blue: 0.34).opacity(0.08),
                inactiveMatrixBorder: Color(red: 0.18, green: 0.23, blue: 0.34).opacity(0.05),
                activeMatrixBorder: Color.white,
                primaryText: Color(red: 0.12, green: 0.15, blue: 0.22),
                secondaryText: Color(red: 0.43, green: 0.49, blue: 0.60),
                online: Color(red: 0.12, green: 0.68, blue: 0.40),
                offline: Color(red: 0.92, green: 0.63, blue: 0.15),
                cpuAccent: Color(red: 0.93, green: 0.33, blue: 0.36),
                memoryAccent: Color(red: 0.16, green: 0.70, blue: 0.42),
                metaTint: Color(red: 0.29, green: 0.47, blue: 0.88),
                cardShadow: Color.black.opacity(0.08)
            )
        @unknown default:
            return palette(for: .dark)
        }
    }
}
