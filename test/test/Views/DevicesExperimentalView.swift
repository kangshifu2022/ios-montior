import SwiftUI
import UniformTypeIdentifiers

struct DevicesExperimentalView: View {
    @ObservedObject var store: ServerStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ExperimentalHomeTheme.storageKey) private var experimentalHomeThemeRawValue = ExperimentalHomeTheme.system.rawValue
    @AppStorage(ExperimentalHomeCardView.storageKey) private var experimentalHomeCardViewRawValue = ExperimentalHomeCardView.detailed.rawValue
    @State private var selectedServer: ServerConfig?
    @State private var draggedServerID: UUID?

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

    private var homeCardView: ExperimentalHomeCardView {
        ExperimentalHomeCardView(rawValue: experimentalHomeCardViewRawValue) ?? .detailed
    }

    private var appEdition: ExperimentalAppEdition {
        .pro
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    pageHeader

                    if store.servers.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: homeCardView == .detailed ? 18 : 10) {
                            ForEach(store.servers) { server in
                                reorderableCard(for: server)
                            }
                        }
                        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: store.servers)
                        .onDrop(of: [UTType.text], delegate: ExperimentalServerListDropDelegate(draggedServerID: $draggedServerID))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .refreshable {
                await store.refreshAllIfNeeded(forceDynamic: true, forceStatic: true)
            }
            .background(palette.pageBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ExperimentalViewToggleIcon(
                        mode: homeCardView,
                        color: palette.primaryText
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        experimentalHomeCardViewRawValue = homeCardView == .detailed
                            ? ExperimentalHomeCardView.compact.rawValue
                            : ExperimentalHomeCardView.detailed.rawValue
                    }
                    .accessibilityLabel(homeCardView == .detailed ? "切换到缩略视图" : "切换到详细视图")
                    .accessibilityAddTraits(.isButton)
                }
            }
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

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("概览")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(palette.primaryText)
                .tracking(-0.6)

            HStack(alignment: .center, spacing: 8) {
                Text("iMonitor")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .opacity(0.94)

                if appEdition == .pro {
                    Text("PRO")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(palette.memoryAccent)
                        .tracking(0.6)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(palette.memoryAccent.opacity(palette.isDark ? 0.14 : 0.10))
                        .clipShape(Capsule())
                        .offset(y: 1)
                }
            }

            Text("一站式 Linux 设备监控平台")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText)
                .opacity(0.92)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func reorderableCard(for server: ServerConfig) -> some View {
        let isDragged = draggedServerID == server.id

        Group {
            if homeCardView == .detailed {
                ExperimentalServerCard(
                    config: server,
                    stats: store.stats(for: server),
                    palette: palette
                ) {
                    selectedServer = server
                }
            } else {
                ExperimentalCompactServerCard(
                    config: server,
                    stats: store.stats(for: server),
                    palette: palette
                ) {
                    selectedServer = server
                }
            }
        }
        .scaleEffect(isDragged ? 1.02 : 1)
        .opacity(isDragged ? 0.72 : 1)
        .shadow(color: isDragged ? palette.cardShadow.opacity(1.2) : .clear, radius: 16, x: 0, y: 10)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isDragged)
        .onDrag {
            draggedServerID = server.id
            return NSItemProvider(object: server.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: ExperimentalServerCardDropDelegate(
            targetServer: server,
            store: store,
            draggedServerID: $draggedServerID
        ))
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有服务器")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryText)

            Text("先去设置里添加服务器，首屏卡片就会按当前视图模式展示。")
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

private enum ExperimentalHomeCardView: String {
    case detailed
    case compact

    static let storageKey = "experimentalHomeCardView"
}

private enum ExperimentalAppEdition {
    case standard
    case pro
}

@MainActor
private struct ExperimentalServerCardDropDelegate: DropDelegate {
    let targetServer: ServerConfig
    let store: ServerStore
    @Binding var draggedServerID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggedServerID,
              draggedServerID != targetServer.id,
              let targetIndex = store.servers.firstIndex(where: { $0.id == targetServer.id }) else {
            return
        }

        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            store.moveServer(id: draggedServerID, to: targetIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedServerID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

@MainActor
private struct ExperimentalServerListDropDelegate: DropDelegate {
    @Binding var draggedServerID: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedServerID = nil
        return true
    }
}

private struct ExperimentalViewToggleIcon: View {
    let mode: ExperimentalHomeCardView
    let color: Color

    var body: some View {
        Group {
            if mode == .detailed {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(color.opacity(0.88), lineWidth: 1.2)
                    .frame(width: 15, height: 11)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                            .stroke(color.opacity(0.35), lineWidth: 0.9)
                            .frame(width: 9, height: 5.5)
                    }
            } else {
                VStack(spacing: 2.4) {
                    compactLine(width: 15, opacity: 0.96)
                    compactLine(width: 12.5, opacity: 0.80)
                    compactLine(width: 14, opacity: 0.64)
                }
            }
        }
        .frame(width: 20, height: 20)
    }

    private func compactLine(width: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(color.opacity(opacity))
            .frame(width: width, height: 2.1)
    }
}

private struct ExperimentalCompactServerCard: View {
    let config: ServerConfig
    let stats: ServerStats?
    let palette: ExperimentalHomePalette
    let onOpenDetail: () -> Void

    private var isOnline: Bool {
        stats?.isOnline == true
    }

    private var cpuText: String {
        percentageText(stats?.cpuUsage)
    }

    private var memText: String {
        percentageText(stats?.memUsage)
    }

    private var uploadParts: ExperimentalRateParts {
        ExperimentalRateParts(rawValue: isOnline ? (stats?.uploadSpeed ?? "--") : "--")
    }

    private var downloadParts: ExperimentalRateParts {
        ExperimentalRateParts(rawValue: isOnline ? (stats?.downloadSpeed ?? "--") : "--")
    }

    private var cpuTint: Color {
        cpuUsageTint(for: stats?.cpuUsage)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(config.name)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(palette.primaryText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                ExperimentalCompactMetricCapsule(
                    title: "CPU",
                    value: cpuText,
                    isActive: isOnline,
                    accent: cpuTint,
                    palette: palette
                )

                ExperimentalCompactMetricCapsule(
                    title: "MEM",
                    value: memText,
                    isActive: isOnline,
                    accent: palette.memoryAccent,
                    palette: palette
                )

                ExperimentalCompactRateCapsule(
                    symbol: "↑",
                    parts: uploadParts,
                    palette: palette
                )

                ExperimentalCompactRateCapsule(
                    symbol: "↓",
                    parts: downloadParts,
                    palette: palette
                )
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
        .shadow(color: palette.cardShadow, radius: 14, x: 0, y: 8)
    }

    private func percentageText(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int((min(max(value, 0), 1) * 100).rounded()))"
    }

    private func cpuUsageTint(for value: Double?) -> Color {
        guard let value else {
            return palette.secondaryText
        }

        switch value {
        case ..<0.20:
            return Color(red: 0.20, green: 0.78, blue: 0.36)
        case ..<0.40:
            return Color(red: 0.53, green: 0.82, blue: 0.18)
        case ..<0.60:
            return Color(red: 0.95, green: 0.78, blue: 0.18)
        case ..<0.80:
            return Color(red: 0.96, green: 0.52, blue: 0.20)
        default:
            return Color(red: 0.90, green: 0.26, blue: 0.24)
        }
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
        VStack(alignment: .leading, spacing: 10) {
            header

            HStack(alignment: .center, spacing: 18) {
                metricRings
                infoPanel
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
        .padding(.horizontal, 20)
        .padding(.top, 7)
        .padding(.bottom, 14)
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
                        symbol: "cpuchip",
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
        HStack(spacing: 16) {
            ExperimentalMetricTile(
                label: "CPU %",
                percentage: isOnline ? percentageValue(stats?.cpuUsage) : nil,
                valueTint: cpuUsageTint,
                ringStyle: .standard,
                palette: palette
            )

            ExperimentalMetricTile(
                label: "MEM %",
                percentage: isOnline ? percentageValue(stats?.memUsage) : nil,
                valueTint: palette.memoryAccent,
                ringStyle: .memoryGradient,
                palette: palette
            )
        }
        .frame(width: 150, height: 96, alignment: .leading)
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ExperimentalInfoMetricRow(
                title: "Net",
                items: networkMetrics,
                accent: palette.memoryAccent,
                palette: palette
            )

            ExperimentalInfoMetricRow(
                title: "Disk",
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
        .frame(maxWidth: .infinity, minHeight: 87, maxHeight: 87, alignment: .leading)
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

        return normalizedUptimeDisplay(from: uptimeText)
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

    private var cpuUsageTint: Color {
        guard let usage = stats?.cpuUsage, isOnline else {
            return palette.secondaryText
        }

        switch usage {
        case ..<0.20:
            return Color(red: 0.20, green: 0.78, blue: 0.36)
        case ..<0.40:
            return Color(red: 0.53, green: 0.82, blue: 0.18)
        case ..<0.60:
            return Color(red: 0.95, green: 0.78, blue: 0.18)
        case ..<0.80:
            return Color(red: 0.96, green: 0.52, blue: 0.20)
        default:
            return Color(red: 0.90, green: 0.26, blue: 0.24)
        }
    }

    private var networkMetrics: [ExperimentalInlineMetricDescriptor] {
        [
            inlineMetric(id: "network-upload", value: uploadSpeedText, marker: "↑"),
            inlineMetric(id: "network-download", value: downloadSpeedText, marker: "↓")
        ]
    }

    private var diskMetrics: [ExperimentalInlineMetricDescriptor] {
        [
            inlineMetric(id: "disk-read", value: diskReadSpeedText, marker: "R"),
            inlineMetric(id: "disk-write", value: diskWriteSpeedText, marker: "W")
        ]
    }

    private func inlineMetric(id: String, value: String, marker: String) -> ExperimentalInlineMetricDescriptor {
        let parts = ExperimentalRateParts(rawValue: value)
        return ExperimentalInlineMetricDescriptor(id: id, parts: parts, marker: marker)
    }

    private func percentageValue(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }

    private func normalizedUptimeDisplay(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "--"
        }

        if let seconds = Double(trimmed), seconds >= 0 {
            return uptimeDisplay(days: Int(seconds) / 86_400,
                                 hours: (Int(seconds) % 86_400) / 3_600,
                                 minutes: (Int(seconds) % 3_600) / 60)
        }

        let lowercased = trimmed.lowercased()

        if let match = lowercased.range(of: #"(\d+)\s*d\s*(\d+)\s*h\s*(\d+)\s*m"#, options: .regularExpression) {
            return compactUptimeToken(String(lowercased[match]))
        }

        if let match = lowercased.range(of: #"(\d+)\s*h\s*(\d+)\s*m"#, options: .regularExpression) {
            return compactUptimeToken(String(lowercased[match]))
        }

        if let match = lowercased.range(of: #"(\d+)\s*day[s]?,?\s*(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let token = String(lowercased[match])
            let numbers = token.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if numbers.count >= 3 {
                return uptimeDisplay(days: numbers[0], hours: numbers[1], minutes: numbers[2])
            }
        }

        if let match = lowercased.range(of: #"up\s+(\d+)\s+days?,?\s+(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let token = String(lowercased[match])
            let numbers = token.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if numbers.count >= 3 {
                return uptimeDisplay(days: numbers[0], hours: numbers[1], minutes: numbers[2])
            }
        }

        if let match = trimmed.range(of: #"(\d+)\s*天\s*(\d+)\s*小时\s*(\d+)\s*分"#, options: .regularExpression) {
            let token = String(trimmed[match])
            let numbers = token.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if numbers.count >= 3 {
                return uptimeDisplay(days: numbers[0], hours: numbers[1], minutes: numbers[2])
            }
        }

        if lowercased.hasPrefix("up ") {
            return String(trimmed.dropFirst(3))
        }

        return trimmed
    }

    private func compactUptimeToken(_ token: String) -> String {
        let numbers = token.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }

        if token.contains("d"), numbers.count >= 3 {
            return uptimeDisplay(days: numbers[0], hours: numbers[1], minutes: numbers[2])
        }

        if numbers.count >= 2 {
            return "\(numbers[0])h \(numbers[1])m"
        }

        return token
    }

    private func uptimeDisplay(days: Int, hours: Int, minutes: Int) -> String {
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    private func temperatureText(for value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }
}

private struct ExperimentalMetricTile: View {
    let label: String
    let percentage: Int?
    let valueTint: Color
    var ringStyle: ExperimentalRingStyle = .standard
    let palette: ExperimentalHomePalette

    var body: some View {
        ExperimentalUsageRing(
            label: label,
            percentage: percentage,
            tint: valueTint,
            ringStyle: ringStyle,
            palette: palette
        )
        .frame(width: 65, height: 65)
        .opacity(percentage == nil ? 0.78 : 1)
    }
}

private struct ExperimentalCompactMetricCapsule: View {
    let title: String
    let value: String
    let isActive: Bool
    let accent: Color
    let palette: ExperimentalHomePalette

    private var valueColor: Color {
        isActive ? accent : palette.secondaryText.opacity(0.38)
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText)

            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(palette.subcardBackground)
        .clipShape(Capsule())
    }
}

private struct ExperimentalCompactRateCapsule: View {
    let symbol: String
    let parts: ExperimentalRateParts
    let palette: ExperimentalHomePalette

    private var valueColor: Color {
        parts.hasRenderableValue ? palette.memoryAccent : palette.secondaryText.opacity(0.38)
    }

    private var metaColor: Color {
        parts.hasRenderableValue ? palette.memoryAccent : palette.secondaryText.opacity(0.28)
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(symbol)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(metaColor)

            Text(parts.displayNumber)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
                .monospacedDigit()

            Text(parts.compactUnit)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(metaColor)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(palette.subcardBackground)
        .clipShape(Capsule())
    }
}

private enum ExperimentalRingStyle {
    case standard
    case memoryGradient
}

private struct ExperimentalUsageRing: View {
    let label: String
    let percentage: Int?
    let tint: Color
    let ringStyle: ExperimentalRingStyle
    let palette: ExperimentalHomePalette

    private var normalizedValue: Double {
        Double(min(max(percentage ?? 0, 0), 100)) / 100
    }

    private var trackColor: Color {
        switch ringStyle {
        case .standard:
            return palette.isDark ? Color.white.opacity(0.14) : Color(.systemGray5)
        case .memoryGradient:
            return palette.isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
        }
    }

    private var activeStrokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 8, lineCap: ringStyle == .memoryGradient ? .round : .butt)
    }

    private var remainderStrokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: 8, lineCap: .round)
    }

    private var activeStroke: AnyShapeStyle {
        switch ringStyle {
        case .standard:
            return AnyShapeStyle(tint)
        case .memoryGradient:
            return AnyShapeStyle(
                AngularGradient(
                    colors: [
                        Color(red: 0.52, green: 0.92, blue: 0.31),
                        Color(red: 0.23, green: 0.80, blue: 0.14),
                        Color(red: 0.05, green: 0.62, blue: 0.43),
                        Color(red: 0.11, green: 0.72, blue: 0.48),
                        Color(red: 0.44, green: 0.88, blue: 0.24)
                    ],
                    center: .center
                )
            )
        }
    }

    private var availableStroke: AnyShapeStyle {
        AnyShapeStyle(
            AngularGradient(
                colors: [
                    Color(red: 0.76, green: 0.96, blue: 0.58),
                    Color(red: 0.63, green: 0.92, blue: 0.49),
                    Color(red: 0.53, green: 0.88, blue: 0.45),
                    Color(red: 0.64, green: 0.93, blue: 0.56),
                    Color(red: 0.78, green: 0.97, blue: 0.68)
                ],
                center: .center
            )
        )
    }

    var body: some View {
        ZStack {
            if ringStyle == .memoryGradient {
                if normalizedValue < 1 {
                    Circle()
                        .trim(from: normalizedValue, to: 1)
                        .stroke(availableStroke, style: remainderStrokeStyle)
                        .rotationEffect(.degrees(-90))
                }

                if normalizedValue > 0 {
                    Circle()
                        .trim(from: 0, to: normalizedValue)
                        .stroke(activeStroke, style: activeStrokeStyle)
                        .rotationEffect(.degrees(-90))
                }

                Circle()
                    .stroke(
                        palette.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03),
                        lineWidth: 1
                    )
                    .padding(-5)
            } else {
                Circle()
                    .stroke(trackColor, lineWidth: 8)

                Circle()
                    .trim(from: 0, to: normalizedValue)
                    .stroke(
                        activeStroke,
                        style: activeStrokeStyle
                    )
                    .rotationEffect(.degrees(-90))
            }

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
            .font(.system(size: 21, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
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
                .frame(width: 58, alignment: .leading)
                .offset(x: 11)

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
        .frame(height: 29, alignment: .center)
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
                .frame(width: 58, alignment: .leading)
                .offset(x: 11)

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 29, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExperimentalInlineMetric: View {
    let item: ExperimentalInlineMetricDescriptor
    let accent: Color
    let palette: ExperimentalHomePalette

    private var isActive: Bool {
        item.parts.hasRenderableValue
    }

    private var valueColor: Color {
        isActive ? accent : palette.secondaryText.opacity(0.28)
    }

    private var metaColor: Color {
        isActive ? accent : palette.secondaryText.opacity(0.24)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(item.parts.displayNumber)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)

            if !item.parts.compactUnit.isEmpty {
                Text(item.parts.compactUnit)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(metaColor)
                    .monospacedDigit()
            }

            Text(item.marker)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(metaColor)
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
            ExperimentalHeaderSymbol(
                symbol: symbol,
                color: palette.secondaryText
            )

            Text(value)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(tint ?? palette.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

private struct ExperimentalHeaderSymbol: View {
    let symbol: String
    let color: Color

    var body: some View {
        Group {
            if symbol == "cpuchip" {
                ExperimentalCPUChipIcon(color: color)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(color)
                    .frame(width: 16, height: 16)
            }
        }
    }
}

private struct ExperimentalCPUChipIcon: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.2, style: .continuous)
                .stroke(color.opacity(0.9), lineWidth: 1.2)
                .frame(width: 12, height: 12)

            RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                .stroke(color.opacity(0.55), lineWidth: 0.9)
                .frame(width: 7, height: 7)

            ForEach([-1, 1], id: \.self) { side in
                VStack(spacing: 1.8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule(style: .continuous)
                            .fill(color.opacity(0.9))
                            .frame(width: 1.2, height: 2.4)
                    }
                }
                .offset(x: CGFloat(side) * 7.5)
            }

            ForEach([-1, 1], id: \.self) { side in
                HStack(spacing: 1.8) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule(style: .continuous)
                            .fill(color.opacity(0.9))
                            .frame(width: 2.4, height: 1.2)
                    }
                }
                .offset(y: CGFloat(side) * 7.5)
            }
        }
        .frame(width: 16, height: 16)
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
            number = "0"
            unit = ""
            displayNumber = "0"
            numericValue = 0
            numericAmount = 0
            compactUnit = "K"
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
