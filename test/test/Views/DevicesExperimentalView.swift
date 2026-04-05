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
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有服务器")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryText)

            Text("实验版首屏已经切到环形指标方案。先去设置里添加服务器，我们再继续打磨卡片气质。")
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
                Text("Device Pulse Board")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(palette.primaryText)

                Text("实验版设备卡片已经切到新首屏样式，左侧看 CPU / MEM 圆环，右侧对照 NET / I/O 速率，顶部保留温度和终端入口。")
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
                        title: "样式",
                        value: "Ring",
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
                        title: "样式",
                        value: "Ring",
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
        VStack(alignment: .leading, spacing: 18) {
            header

            ViewThatFits {
                HStack(alignment: .center, spacing: 22) {
                    metricRings
                    infoPanel
                }

                VStack(alignment: .leading, spacing: 18) {
                    metricRings
                    infoPanel
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 19, weight: .light, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

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

    private var metricRings: some View {
        HStack(spacing: 14) {
            ExperimentalMetricTile(
                label: "CPU %",
                percentage: isOnline ? percentageValue(stats?.cpuUsage) : nil,
                valueTint: palette.memoryAccent,
                palette: palette
            )

            ExperimentalMetricTile(
                label: "MEM %",
                percentage: isOnline ? percentageValue(stats?.memUsage) : nil,
                valueTint: palette.memoryAccent,
                palette: palette
            )
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            ExperimentalInfoMetricRow(
                title: "Network",
                items: networkMetrics,
                accent: palette.memoryAccent,
                palette: palette
            )

            ExperimentalInfoMetricRow(
                title: "Disk I/O",
                items: diskMetrics,
                accent: palette.memoryAccent,
                palette: palette
            )

            ExperimentalInfoValueRow(
                title: "Uptime",
                value: uptimeDisplayText,
                palette: palette
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var uptimeDisplayText: String {
        guard uptimeText != "--" else {
            return "--"
        }

        let trimmed = uptimeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("up ") {
            return String(trimmed.dropFirst(3))
        }
        return trimmed
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

    private var networkMetrics: [ExperimentalInlineMetricDescriptor] {
        [
            inlineMetric(id: "network-upload", value: uploadSpeedText, marker: "↑"),
            inlineMetric(id: "network-download", value: downloadSpeedText, marker: "↓")
        ].compactMap { $0 }
    }

    private var diskMetrics: [ExperimentalInlineMetricDescriptor] {
        [
            inlineMetric(id: "disk-read", value: diskReadSpeedText, marker: "R"),
            inlineMetric(id: "disk-write", value: diskWriteSpeedText, marker: "W")
        ].compactMap { $0 }
    }

    private func inlineMetric(id: String, value: String, marker: String) -> ExperimentalInlineMetricDescriptor? {
        let parts = ExperimentalRateParts(rawValue: value)
        guard parts.hasRenderableValue else {
            return nil
        }

        return ExperimentalInlineMetricDescriptor(id: id, parts: parts, marker: marker)
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
    let valueTint: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        ExperimentalUsageRing(
            label: label,
            percentage: percentage,
            tint: valueTint,
            palette: palette
        )
        .frame(width: 94, height: 94)
        .opacity(percentage == nil ? 0.78 : 1)
    }
}

private struct ExperimentalUsageRing: View {
    let label: String
    let percentage: Int?
    let tint: Color
    let palette: ExperimentalHomePalette

    private var normalizedValue: Double {
        Double(min(max(percentage ?? 0, 0), 100)) / 100
    }

    private var trackColor: Color {
        palette.isDark ? Color.white.opacity(0.14) : Color(.systemGray5)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: 9)

            Circle()
                .trim(from: 0, to: normalizedValue)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 9, lineCap: .butt)
                )
                .rotationEffect(.degrees(-90))

            ExperimentalRingPercentageText(
                label: label,
                percentage: percentage,
                tint: tint,
                palette: palette
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: percentage ?? -1)
    }
}

private struct ExperimentalRingPercentageText: View {
    let label: String
    let percentage: Int?
    let tint: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(spacing: 1) {
            Group {
                if let percentage {
                    Text("\(percentage)")
                        .contentTransition(.numericText(value: Double(percentage)))
                        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: percentage)
                } else {
                    Text("--")
                }
            }
            .font(.system(size: 28, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText)
                .tracking(0.2)
        }
        .foregroundColor(tint)
    }
}

private struct ExperimentalInlineMetricDescriptor: Identifiable {
    let id: String
    let parts: ExperimentalRateParts
    let marker: String
}

private struct ExperimentalInfoMetricRow: View {
    let title: String
    let items: [ExperimentalInlineMetricDescriptor]
    let accent: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText)
                .frame(width: 66, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                ForEach(items) { item in
                    ExperimentalInlineMetric(
                        item: item,
                        accent: accent,
                        palette: palette
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExperimentalInfoValueRow: View {
    let title: String
    let value: String
    let palette: ExperimentalHomePalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText)
                .frame(width: 66, alignment: .leading)

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(palette.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExperimentalInlineMetric: View {
    let item: ExperimentalInlineMetricDescriptor
    let accent: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(item.parts.displayNumber)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(accent)
                .monospacedDigit()
                .lineLimit(1)

            if !item.parts.compactUnit.isEmpty {
                Text(item.parts.compactUnit)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(palette.secondaryText.opacity(0.82))
                    .monospacedDigit()
            }

            Text(item.marker)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(accent)
                .lineLimit(1)
        }
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
    let numericAmount: Double?
    let compactUnit: String
    let hasRenderableValue: Bool

    init(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(of: " ", with: "")

        guard !compact.isEmpty, compact != "--" else {
            number = "--"
            unit = ""
            displayNumber = "--"
            numericValue = nil
            numericAmount = nil
            compactUnit = ""
            hasRenderableValue = false
            return
        }

        let splitIndex = compact.firstIndex(where: { character in
            !character.isNumber && character != "." && character != "," && character != "-"
        }) ?? compact.endIndex

        let parsedNumber = String(compact[..<splitIndex])
        let parsedUnit = splitIndex == compact.endIndex ? "" : String(compact[splitIndex...])

        number = parsedNumber.isEmpty ? compact : parsedNumber
        unit = parsedNumber.isEmpty ? "" : parsedUnit
        let amount = ExperimentalRateParts.doubleValue(from: number)
        let integerValue = ExperimentalRateParts.integerDisplay(from: number)
        numericAmount = amount
        displayNumber = ExperimentalRateParts.displayText(from: amount, fallback: number)
        numericValue = integerValue
        compactUnit = ExperimentalRateParts.compactUnit(from: unit)
        hasRenderableValue = (amount ?? 0) > 0.000_1
    }

    private static func integerDisplay(from rawNumber: String) -> Int? {
        let normalized = rawNumber.replacingOccurrences(of: ",", with: ".")

        if let value = Double(normalized) {
            return Int(value.rounded(.towardZero))
        }

        return nil
    }

    private static func doubleValue(from rawNumber: String) -> Double? {
        let normalized = rawNumber.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static func compactUnit(from rawUnit: String) -> String {
        switch rawUnit.lowercased() {
        case "k/s":
            return "K"
        case "mb/s":
            return "M"
        case "gb/s":
            return "G"
        case "b/s":
            return "B"
        default:
            return rawUnit.uppercased()
        }
    }

    private static func displayText(from amount: Double?, fallback: String) -> String {
        guard let amount else {
            return fallback
        }

        if amount >= 10 {
            return String(Int(amount.rounded(.towardZero)))
        }

        if amount >= 1 {
            return amount == floor(amount) ? String(Int(amount)) : String(format: "%.1f", amount)
        }

        return String(format: "%.1f", amount)
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
