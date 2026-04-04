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
            .refreshable {
                await store.refreshAllIfNeeded(forceDynamic: true, forceStatic: true)
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

                Text("实验版设备卡片已经切到新首屏样式，左侧看 CPU / MEM 点阵，右侧对照 WLAN / DISK 速率，顶部保留温度和终端入口。")
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
        VStack(alignment: .leading, spacing: 24) {
            header

            HStack(alignment: .bottom, spacing: 14) {
                ExperimentalMetricTile(
                    label: "CPU",
                    percentage: isOnline ? percentageValue(stats?.cpuUsage) : nil,
                    matrixTint: palette.matrixAccent,
                    valueTint: palette.memoryAccent,
                    palette: palette
                )

                ExperimentalMetricTile(
                    label: "MEM",
                    percentage: isOnline ? percentageValue(stats?.memUsage) : nil,
                    matrixTint: palette.matrixAccent,
                    valueTint: palette.memoryAccent,
                    palette: palette
                )

                ExperimentalRateColumn(
                    title: "WLAN",
                    primaryValue: uploadSpeedText,
                    primaryCaption: "upload",
                    secondaryValue: downloadSpeedText,
                    secondaryCaption: "down",
                    accent: palette.memoryAccent,
                    palette: palette
                )

                ExperimentalRateColumn(
                    title: "DISK",
                    primaryValue: diskReadSpeedText,
                    primaryCaption: "read",
                    secondaryValue: diskWriteSpeedText,
                    secondaryCaption: "write",
                    accent: palette.memoryAccent,
                    palette: palette
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 29, weight: .light, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            HStack(spacing: 14) {
                if let cpuTemperatureText {
                    ExperimentalHeaderBadge(
                        symbol: "microchip",
                        value: cpuTemperatureText,
                        palette: palette
                    )
                }

                if let wirelessTemperatureText {
                    ExperimentalHeaderBadge(
                        symbol: "wifi",
                        value: wirelessTemperatureText,
                        palette: palette
                    )
                }

                if !isOnline {
                    ExperimentalHeaderBadge(
                        symbol: "exclamationmark.triangle",
                        value: offlineText,
                        palette: palette,
                        tint: palette.offline
                    )
                } else if cpuTemperatureText == nil && wirelessTemperatureText == nil, headerUptimeText != "--" {
                    ExperimentalHeaderBadge(
                        symbol: "clock",
                        value: headerUptimeText,
                        palette: palette
                    )
                }

                terminalButton
            }
        }
    }

    private var terminalButton: some View {
        Button(action: { showTerminal = true }) {
            Image(systemName: "terminal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(terminalButtonForeground)
                .frame(width: 30, height: 30)
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

    private var cpuTemperatureText: String? {
        guard isOnline, let value = stats?.cpuTemperatureC else {
            return nil
        }
        return temperatureText(for: value)
    }

    private var wirelessTemperatureText: String? {
        guard isOnline else {
            return nil
        }

        if let value = stats?.wifi5TemperatureC {
            return temperatureText(for: value)
        }

        if let value = stats?.wifi24TemperatureC {
            return temperatureText(for: value)
        }

        return nil
    }

    private var offlineText: String {
        "offline"
    }

    private func percentageValue(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }

    private func temperatureText(for value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }
}

private struct ExperimentalMetricTile: View {
    let label: String
    let percentage: Int?
    let matrixTint: Color
    let valueTint: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ExperimentalDotMatrix(
                    percentage: percentage,
                    tint: matrixTint,
                    palette: palette
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 86)

                ExperimentalRollingPercentageText(
                    percentage: percentage,
                    tint: valueTint
                )
                .frame(width: 68, alignment: .center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(label)
                .font(.system(size: 16, weight: .light, design: .rounded))
                .foregroundColor(palette.secondaryText)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .layoutPriority(1)
        .opacity(percentage == nil ? 0.78 : 1)
    }
}

private struct ExperimentalRateColumn: View {
    let title: String
    let primaryValue: String
    let primaryCaption: String
    let secondaryValue: String
    let secondaryCaption: String
    let accent: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExperimentalRateValue(
                value: primaryValue,
                caption: primaryCaption,
                accent: accent,
                palette: palette
            )

            ExperimentalRateValue(
                value: secondaryValue,
                caption: secondaryCaption,
                accent: accent,
                palette: palette
            )

            Text(title)
                .font(.system(size: 16, weight: .light, design: .rounded))
                .foregroundColor(palette.secondaryText)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .layoutPriority(1)
    }
}

private struct ExperimentalRateValue: View {
    let value: String
    let caption: String
    let accent: Color
    let palette: ExperimentalHomePalette

    private var parts: ExperimentalRateParts {
        ExperimentalRateParts(rawValue: value)
    }

    private var valueColor: Color {
        guard let numericValue = parts.numericValue, numericValue > 0 else {
            return palette.secondaryText.opacity(palette.isDark ? 0.72 : 0.84)
        }
        return accent
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Group {
                if let numericValue = parts.numericValue {
                    Text("\(numericValue)")
                        .contentTransition(.numericText(value: Double(numericValue)))
                        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: numericValue)
                } else {
                    Text(parts.displayNumber)
                }
            }
                .font(.system(size: 31, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: -2) {
                Text(parts.unit.isEmpty ? "--" : parts.unit)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundColor(palette.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(caption)
                    .font(.system(size: 9, weight: .regular, design: .rounded))
                    .foregroundColor(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            .frame(width: 34, height: 32, alignment: .center)
        }
        .frame(height: 40, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExperimentalRollingPercentageText: View {
    let percentage: Int?
    let tint: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Group {
                if let percentage {
                    Text("\(percentage)")
                        .contentTransition(.numericText(value: Double(percentage)))
                        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: percentage)
                } else {
                    Text("--")
                }
            }

            Text("%")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .opacity(percentage == nil ? 0 : 0.62)
        }
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .foregroundColor(tint)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
}

private struct ExperimentalHeaderBadge: View {
    let symbol: String
    let value: String
    let palette: ExperimentalHomePalette
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.secondaryText)

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(tint ?? palette.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private struct ExperimentalRateParts {
    let number: String
    let unit: String
    let displayNumber: String
    let numericValue: Int?

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(of: " ", with: "")

        guard !compact.isEmpty, compact != "--" else {
            number = "--"
            unit = ""
            displayNumber = "--"
            numericValue = nil
            return
        }

        let splitIndex = compact.firstIndex(where: { character in
            !character.isNumber && character != "." && character != "," && character != "-"
        }) ?? compact.endIndex

        let parsedNumber = String(compact[..<splitIndex])
        let parsedUnit = splitIndex == compact.endIndex ? "" : String(compact[splitIndex...])

        number = parsedNumber.isEmpty ? compact : parsedNumber
        unit = parsedNumber.isEmpty ? "" : parsedUnit
        let integerValue = ExperimentalRateParts.integerDisplay(from: number)
        displayNumber = integerValue.map(String.init) ?? number
        numericValue = integerValue
    }

    private static func integerDisplay(from rawNumber: String) -> Int? {
        let normalized = rawNumber.replacingOccurrences(of: ",", with: ".")

        if let value = Double(normalized) {
            return Int(value.rounded(.towardZero))
        }

        return nil
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
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)
            let horizontalSpacing: CGFloat = width < 120 ? 1.4 : 1.8
            let verticalSpacing: CGFloat = height < 72 ? 1.2 : 1.5
            let tileWidth = max((width - (horizontalSpacing * CGFloat(size - 1))) / CGFloat(size), 1.8)
            let tileHeight = max((height - (verticalSpacing * CGFloat(size - 1))) / CGFloat(size), 1.8)
            let dashWidth = max(tileWidth * 0.88, 1.8)
            let dashHeight = max(tileHeight * 0.30, 1.2)

            VStack(spacing: verticalSpacing) {
                ForEach(0..<size, id: \.self) { visualRow in
                    HStack(spacing: horizontalSpacing) {
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
                                .frame(width: tileWidth, height: tileHeight)
                                .scaleEffect(isActive ? 0.94 : 0.8)
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
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
            return tint.opacity(palette.isDark ? 0.28 : 0.22)
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
    let matrixAccent: Color
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
                matrixAccent: Color(red: 0.18, green: 0.45, blue: 0.24),
                inactiveMatrixBorder: Color.white.opacity(0.02),
                activeMatrixBorder: Color.white,
                primaryText: .primary,
                secondaryText: .secondary,
                online: Color(red: 0.22, green: 0.86, blue: 0.53),
                offline: Color(red: 0.98, green: 0.73, blue: 0.24),
                cpuAccent: Color(red: 0.98, green: 0.36, blue: 0.39),
                memoryAccent: Color(red: 16.0 / 255.0, green: 192.0 / 255.0, blue: 7.0 / 255.0),
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
                matrixAccent: Color(red: 0.23, green: 0.56, blue: 0.30),
                inactiveMatrixBorder: Color.white.opacity(0.34),
                activeMatrixBorder: Color.white,
                primaryText: .primary,
                secondaryText: .secondary,
                online: Color(red: 0.12, green: 0.68, blue: 0.40),
                offline: Color(red: 0.92, green: 0.63, blue: 0.15),
                cpuAccent: Color(red: 0.93, green: 0.33, blue: 0.36),
                memoryAccent: Color(red: 16.0 / 255.0, green: 192.0 / 255.0, blue: 7.0 / 255.0),
                metaTint: Color(red: 0.29, green: 0.47, blue: 0.88),
                cardShadow: Color.black.opacity(0.16)
            )
        @unknown default:
            return palette(for: .dark)
        }
    }
}
