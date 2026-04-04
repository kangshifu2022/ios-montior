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
                Text("10 x 10 Dash Matrix")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(palette.primaryText)

                Text("首屏卡片先切成 2 x 2 四分区，左边保留点阵读数，右边放网络和磁盘速率，方便一起比较。")
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
    @State private var showTerminal = false

    private var isOnline: Bool {
        stats?.isOnline == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 10) {
                    ExperimentalMetricTile(
                        label: "CPU",
                        percentage: percentageValue(stats?.cpuUsage),
                        tint: palette.memoryAccent,
                        palette: palette
                    )

                    ExperimentalMetricTile(
                        label: "MEM",
                        percentage: percentageValue(stats?.memUsage),
                        tint: palette.memoryAccent,
                        palette: palette
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: 10) {
                    ExperimentalRateTile(
                        title: "网络速率",
                        leadingLabel: "下行",
                        leadingValue: downloadSpeedText,
                        leadingTint: palette.online,
                        trailingLabel: "上行",
                        trailingValue: uploadSpeedText,
                        trailingTint: palette.metaTint,
                        palette: palette
                    )

                    ExperimentalRateTile(
                        title: "磁盘速率",
                        leadingLabel: "读取",
                        leadingValue: diskReadSpeedText,
                        leadingTint: palette.cpuAccent,
                        trailingLabel: "写入",
                        trailingValue: diskWriteSpeedText,
                        trailingTint: palette.memoryAccent,
                        palette: palette
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: palette.cardShadow, radius: 20, x: 0, y: 10)
        .fullScreenCover(isPresented: $showTerminal) {
            TerminalView(server: config)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(config.name)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(headerUptimeText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(palette.secondaryText)
                    .lineLimit(1)

                terminalButton
            }
        }
    }

    private var terminalButton: some View {
        Button(action: { showTerminal = true }) {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundColor(terminalButtonForeground)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .disabled(!isOnline)
        .opacity(isOnline ? 1 : 0.45)
    }

    private var downloadSpeedText: String {
        guard isOnline else { return "--" }
        return stats?.downloadSpeed ?? "--"
    }

    private var uploadSpeedText: String {
        guard isOnline else { return "--" }
        return stats?.uploadSpeed ?? "--"
    }

    private var diskReadSpeedText: String {
        guard isOnline else { return "--" }
        return stats?.diskReadSpeed ?? "--"
    }

    private var diskWriteSpeedText: String {
        guard isOnline else { return "--" }
        return stats?.diskWriteSpeed ?? "--"
    }

    private var uptimeText: String {
        let uptime = (stats?.uptime ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return uptime.isEmpty ? "--" : uptime
    }

    private var headerUptimeText: String {
        guard uptimeText != "--" else {
            return "--"
        }

        let raw = uptimeText.lowercased()

        if let range = raw.range(of: #"\d+\s*d"#, options: .regularExpression) {
            return raw[range].replacingOccurrences(of: " ", with: "")
        }

        if let range = raw.range(of: #"\d+\s*day"#, options: .regularExpression) {
            let digits = raw[range].filter(\.isNumber)
            return digits.isEmpty ? "0d" : "\(digits)d"
        }

        if let range = raw.range(of: #"\d+\s*天"#, options: .regularExpression) {
            let digits = raw[range].filter(\.isNumber)
            return digits.isEmpty ? "0d" : "\(digits)d"
        }

        return "--"
    }

    private var terminalButtonForeground: Color {
        isOnline ? palette.primaryText : palette.secondaryText
    }

    private func percentageValue(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }
}

private struct ExperimentalMetricTile: View {
    let label: String
    let percentage: Int?
    let tint: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.secondaryText)

                Spacer(minLength: 0)

                ExperimentalRollingPercentageText(
                    percentage: percentage,
                    palette: palette
                )
            }

            ExperimentalDotMatrix(
                percentage: percentage,
                tint: tint,
                palette: palette
            )
            .frame(height: 72)
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(14)
        .background(palette.subcardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(percentage == nil ? 0.78 : 1)
    }
}

private struct ExperimentalRateTile: View {
    let title: String
    let leadingLabel: String
    let leadingValue: String
    let leadingTint: Color
    let trailingLabel: String
    let trailingValue: String
    let trailingTint: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.secondaryText)

            VStack(alignment: .leading, spacing: 10) {
                ExperimentalRateRow(
                    label: leadingLabel,
                    value: leadingValue,
                    tint: leadingTint,
                    palette: palette
                )

                ExperimentalRateRow(
                    label: trailingLabel,
                    value: trailingValue,
                    tint: trailingTint,
                    palette: palette
                )
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(14)
        .background(palette.subcardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ExperimentalRateRow: View {
    let label: String
    let value: String
    let tint: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint)
                .frame(width: 12, height: 4)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(palette.secondaryText)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(palette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct ExperimentalRollingPercentageText: View {
    let percentage: Int?
    let palette: ExperimentalHomePalette

    var body: some View {
        Group {
            if let percentage {
                Text("\(percentage)%")
                    .contentTransition(.numericText(value: Double(percentage)))
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: percentage)
            } else {
                Text("--")
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundColor(palette.primaryText)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.8)
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
            let spacing: CGFloat = side < 72 ? 1.2 : 1.5
            let tile = max((side - (spacing * CGFloat(size - 1))) / CGFloat(size), 1.8)
            let dashWidth = max(tile * 0.92, 1.8)
            let dashHeight = max(tile * 0.28, 1.2)

            VStack(spacing: spacing) {
                ForEach(0..<size, id: \.self) { visualRow in
                    HStack(spacing: spacing) {
                        ForEach(0..<size, id: \.self) { column in
                            let logicalRow = (size - 1) - visualRow
                            let index = (logicalRow * size) + column
                            let isActive = index < activeCount

                            RoundedRectangle(
                                cornerRadius: dashHeight / 2,
                                style: .continuous
                            )
                                .fill(fillColor(isActive: isActive))
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: dashHeight / 2,
                                        style: .continuous
                                    )
                                        .stroke(borderColor(isActive: isActive), lineWidth: 0.3)
                                )
                                .frame(width: dashWidth, height: dashHeight)
                                .frame(width: tile, height: tile)
                                .scaleEffect(isActive ? 0.94 : 0.8)
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

    private func fillColor(isActive: Bool) -> Color {
        if isActive {
            return tint
        }
        return palette.matrixInactive
    }

    private func borderColor(isActive: Bool) -> Color {
        if isActive {
            return palette.activeMatrixBorder.opacity(palette.isDark ? 0.08 : 0.12)
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

    private static var classicPageBackground: LinearGradient {
        LinearGradient(
            colors: [
                Color(.systemGroupedBackground),
                Color(.systemGroupedBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static var classicCardBackground: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 25.0 / 255.0, green: 26.0 / 255.0, blue: 27.0 / 255.0, alpha: 1)
            }
            return .systemBackground
        })
    }

    private static var classicCardBorder: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.08)
            }
            return UIColor.black.withAlphaComponent(0.06)
        })
    }

    private static var classicSecondaryFill: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.23, green: 0.24, blue: 0.26, alpha: 1)
            }
            return .secondarySystemBackground
        })
    }

    static func palette(for colorScheme: ColorScheme) -> ExperimentalHomePalette {
        switch colorScheme {
        case .dark:
            return ExperimentalHomePalette(
                isDark: true,
                themeName: "深色",
                pageBackground: classicPageBackground,
                heroBackground: classicPageBackground,
                cardBackground: classicCardBackground,
                subcardBackground: classicSecondaryFill,
                cardBorder: classicCardBorder,
                matrixInactive: Color.white.opacity(0.16),
                inactiveMatrixBorder: Color.white.opacity(0.02),
                activeMatrixBorder: Color.white,
                primaryText: .primary,
                secondaryText: .secondary,
                online: Color(red: 0.22, green: 0.86, blue: 0.53),
                offline: Color(red: 0.98, green: 0.73, blue: 0.24),
                cpuAccent: Color(red: 0.98, green: 0.36, blue: 0.39),
                memoryAccent: Color(red: 0.18, green: 0.92, blue: 0.46),
                metaTint: Color(red: 0.35, green: 0.53, blue: 0.93),
                cardShadow: Color.black.opacity(0.16)
            )
        case .light:
            return ExperimentalHomePalette(
                isDark: false,
                themeName: "浅色",
                pageBackground: classicPageBackground,
                heroBackground: classicPageBackground,
                cardBackground: classicCardBackground,
                subcardBackground: classicSecondaryFill,
                cardBorder: classicCardBorder,
                matrixInactive: Color.white.opacity(0.72),
                inactiveMatrixBorder: Color.white.opacity(0.34),
                activeMatrixBorder: Color.white,
                primaryText: .primary,
                secondaryText: .secondary,
                online: Color(red: 0.12, green: 0.68, blue: 0.40),
                offline: Color(red: 0.92, green: 0.63, blue: 0.15),
                cpuAccent: Color(red: 0.93, green: 0.33, blue: 0.36),
                memoryAccent: Color(red: 0.10, green: 0.80, blue: 0.36),
                metaTint: Color(red: 0.29, green: 0.47, blue: 0.88),
                cardShadow: Color.black.opacity(0.16)
            )
        @unknown default:
            return palette(for: .dark)
        }
    }
}
