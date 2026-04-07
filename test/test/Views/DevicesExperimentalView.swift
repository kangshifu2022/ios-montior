import SwiftUI
import UniformTypeIdentifiers

struct DevicesExperimentalView: View {
    private static let cardGroupIndicatorWidth: CGFloat = 2.5
    private static let cardGroupIndicatorHeight: CGFloat = 11

    @ObservedObject var store: ServerStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ExperimentalHomeTheme.storageKey) private var experimentalHomeThemeRawValue = ExperimentalHomeTheme.system.rawValue
    @AppStorage(ExperimentalHomeCardView.storageKey) private var experimentalHomeCardViewRawValue = ExperimentalHomeCardView.detailed.rawValue
    @State private var selectedServer: ServerConfig?
    @State private var terminalServer: ServerConfig?
    @State private var editingServer: ServerConfig?
    @State private var selectedGroupName = ServerConfig.allGroupName
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

    private var availableGroupNames: [String] {
        var groups = [ServerConfig.allGroupName]
        var seenGroups = Set(groups)

        for server in store.servers {
            let group = server.resolvedGroupName
            if seenGroups.insert(group).inserted {
                groups.append(group)
            }
        }

        return groups
    }

    private var activeGroupName: String {
        availableGroupNames.contains(selectedGroupName) ? selectedGroupName : ServerConfig.allGroupName
    }

    private var filteredServers: [ServerConfig] {
        guard activeGroupName != ServerConfig.allGroupName else {
            return store.servers
        }

        return store.servers.filter { $0.resolvedGroupName == activeGroupName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    pageHeader

                    if store.servers.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: homeCardView == .detailed ? 20 : 10) {
                            ForEach(filteredServers) { server in
                                reorderableCard(for: server)
                            }
                        }
                        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: filteredServers)
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
            .navigationDestination(item: $selectedServer) { config in
                DeviceDetailView(config: config, store: store)
            }
            .sheet(item: $editingServer) { server in
                AddServerView(store: store, editingServer: server)
            }
            .fullScreenCover(item: $terminalServer) { config in
                TerminalView(server: config)
            }
            .onChange(of: selectedServer?.id) { _, _ in
                draggedServerID = nil
            }
            .onChange(of: editingServer?.id) { _, _ in
                draggedServerID = nil
            }
            .onChange(of: terminalServer?.id) { _, _ in
                draggedServerID = nil
            }
            .task(id: store.servers.map(\.id)) {
                triggerHomeRefresh()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { break }
                    triggerHomeRefresh(forceDynamic: true)
                }
            }
            .onDisappear {
                draggedServerID = nil
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                Picker("视图模式", selection: homeCardViewSelection) {
                    Image(systemName: "list.bullet")
                        .accessibilityLabel("详细")
                        .tag(ExperimentalHomeCardView.detailed)

                    Image(systemName: "square.grid.2x2")
                        .accessibilityLabel("缩略")
                        .tag(ExperimentalHomeCardView.compact)
                }
                .pickerStyle(.segmented)
                .frame(width: 92)
            }

            Text("概览")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(palette.primaryText)
                .tracking(-0.6)

            if !availableGroupNames.isEmpty {
                groupTabs
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableGroupNames, id: \.self) { groupName in
                    let isSelected = groupName == activeGroupName
                    let groupAccentColor = ExperimentalGroupAccentPalette.color(for: groupName)

                    Button {
                        guard selectedGroupName != groupName else { return }
                        selectedGroupName = groupName
                    } label: {
                        HStack(spacing: 8) {
                            if let groupAccentColor {
                                ExperimentalGroupIndicatorLine(
                                    color: groupAccentColor,
                                    width: 2.5,
                                    height: 11
                                )
                            }

                            Text(groupName)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(isSelected ? selectedGroupTabTextColor : palette.secondaryText)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? selectedGroupTabBackground : groupTabBackground)
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? selectedGroupTabBorderColor : palette.cardBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var selectedGroupTabBackground: Color {
        palette.isDark
            ? Color.white.opacity(0.16)
            : Color.black.opacity(0.82)
    }

    private var selectedGroupTabTextColor: Color {
        .white
    }

    private var selectedGroupTabBorderColor: Color {
        palette.isDark ? Color.white.opacity(0.26) : Color.black.opacity(0.12)
    }

    private var groupTabBackground: Color {
        palette.isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.82)
    }

    private var homeCardViewSelection: Binding<ExperimentalHomeCardView> {
        Binding(
            get: { homeCardView },
            set: { newValue in
                guard newValue != homeCardView else { return }
                setHomeCardView(newValue)
            }
        )
    }

    private func triggerHomeRefresh(
        forceDynamic: Bool = false,
        forceStatic: Bool = false
    ) {
        Task {
            await store.refreshAllIfNeeded(
                forceDynamic: forceDynamic,
                forceStatic: forceStatic
            )
        }
    }

    @ViewBuilder
    private func reorderableCard(for server: ServerConfig) -> some View {
        let serverID = server.id
        let stats = store.stats(for: server)
        let cpuTrendValues = store.cpuUsageHistory(for: serverID)
        let memTrendValues = store.memUsageHistory(for: serverID)
        let isDragged = draggedServerID == serverID
        let showsDetailedCard = homeCardView == .detailed

        Group {
            if showsDetailedCard {
                ExperimentalServerCard(
                    config: server,
                    stats: stats,
                    cpuTrendValues: cpuTrendValues,
                    memTrendValues: memTrendValues,
                    palette: palette
                ) {
                    selectedServer = server
                } onOpenTerminal: {
                    terminalServer = server
                }
            } else {
                ExperimentalCompactServerCard(
                    config: server,
                    stats: stats,
                    palette: palette
                ) {
                    selectedServer = server
                }
            }
        }
        .scaleEffect(isDragged ? 1.02 : 1)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isDragged)
        .onDrag {
            draggedServerID = serverID
            return NSItemProvider(object: serverID.uuidString as NSString)
        }
        .onDrop(of: [UTType.text], delegate: ExperimentalServerCardDropDelegate(
            targetServer: server,
            store: store,
            draggedServerID: $draggedServerID
        ))
        .contextMenu {
            Button {
                editingServer = server
            } label: {
                Label("编辑设备", systemImage: "square.and.pencil")
            }
        }
    }

    private func setHomeCardView(_ nextMode: ExperimentalHomeCardView) {
        experimentalHomeCardViewRawValue = nextMode.rawValue
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

private enum ExperimentalGroupAccentPalette {
    private static let colors: [Color] = [
        Color(red: 0.98, green: 0.49, blue: 0.25),
        Color(red: 0.14, green: 0.76, blue: 0.61),
        Color(red: 0.95, green: 0.73, blue: 0.15),
        Color(red: 0.25, green: 0.68, blue: 0.96),
        Color(red: 0.48, green: 0.83, blue: 0.29),
        Color(red: 0.96, green: 0.38, blue: 0.36),
        Color(red: 0.17, green: 0.82, blue: 0.82),
        Color(red: 0.86, green: 0.59, blue: 0.17)
    ]

    static func color(for groupName: String) -> Color? {
        let normalizedGroupName = ServerConfig.normalizedGroupName(groupName)
        guard normalizedGroupName != ServerConfig.allGroupName else {
            return nil
        }

        var accumulator: UInt64 = 5381
        for scalar in normalizedGroupName.unicodeScalars {
            accumulator = ((accumulator << 5) &+ accumulator) &+ UInt64(scalar.value)
        }

        return colors[Int(accumulator % UInt64(colors.count))]
    }
}

private struct ExperimentalGroupIndicatorLine: View {
    let color: Color
    var width: CGFloat = 24
    var height: CGFloat = 2.5

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: height)
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

    private var headerDisplayName: String {
        let trimmedName = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let maximumCharacters = 20

        guard trimmedName.count > maximumCharacters else {
            return trimmedName
        }

        return String(trimmedName.prefix(maximumCharacters)) + "…"
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

    private var showsFailureState: Bool {
        stats != nil && !isOnline
    }

    private var groupAccentColor: Color? {
        ExperimentalGroupAccentPalette.color(for: config.resolvedGroupName)
    }

    private var deviceNameColor: Color {
        palette.secondaryText.opacity(palette.isDark ? 0.92 : 0.96)
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .center, spacing: 6) {
                if let groupAccentColor {
                    ExperimentalGroupIndicatorLine(
                        color: groupAccentColor,
                        width: DevicesExperimentalView.cardGroupIndicatorWidth,
                        height: DevicesExperimentalView.cardGroupIndicatorHeight
                    )
                }

                HStack(spacing: 5) {
                    Text(headerDisplayName)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(deviceNameColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsFailureState {
                failurePill
                .fixedSize(horizontal: true, vertical: false)
            } else {
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
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenDetail()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
    }

    private var failurePill: some View {
        Text("连接失败")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(Color(red: 0.82, green: 0.29, blue: 0.23))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(red: 0.82, green: 0.29, blue: 0.23).opacity(0.10))
            .clipShape(Capsule())
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
            return Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
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
    let cpuTrendValues: [Double]
    let memTrendValues: [Double]
    let palette: ExperimentalHomePalette
    let onOpenDetail: () -> Void
    let onOpenTerminal: () -> Void

    private var isOnline: Bool {
        stats?.isOnline == true
    }

    private var headerDisplayName: String {
        let trimmedName = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let maximumCharacters = 20

        guard trimmedName.count > maximumCharacters else {
            return trimmedName
        }

        return String(trimmedName.prefix(maximumCharacters)) + "…"
    }

    private var showsFailureState: Bool {
        stats != nil && !isOnline
    }

    private var groupAccentColor: Color? {
        ExperimentalGroupAccentPalette.color(for: config.resolvedGroupName)
    }

    private var deviceNameColor: Color {
        palette.secondaryText.opacity(palette.isDark ? 0.92 : 0.96)
    }

    private var cpuTrendSeries: [Double] {
        metricTrendValues(history: cpuTrendValues, fallback: stats?.cpuUsage)
    }

    private var memTrendSeries: [Double] {
        metricTrendValues(history: memTrendValues, fallback: stats?.memUsage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            balancedMetricRow
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
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if let groupAccentColor {
                    ExperimentalGroupIndicatorLine(
                        color: groupAccentColor,
                        width: DevicesExperimentalView.cardGroupIndicatorWidth,
                        height: DevicesExperimentalView.cardGroupIndicatorHeight
                    )
                }

                Text(headerDisplayName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(deviceNameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
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

                if showsFailureState {
                    connectionFailedBadge
                }

                terminalButton
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }

    private var balancedMetricRow: some View {
        HStack(alignment: .center, spacing: 0) {
            metricSection {
                cpuMetricCell
            }

            metricSection {
                memMetricCell
            }

            metricSection {
                networkMetricCell
            }

            metricSection {
                diskMetricCell
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, maxHeight: 92, alignment: .leading)
    }

    private func metricSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var cpuMetricCell: some View {
        ExperimentalMetricTile(
            label: "CPU %",
            percentage: isOnline ? percentageValue(stats?.cpuUsage) : nil,
            valueTint: cpuUsageTint,
            trendValues: cpuTrendSeries,
            palette: palette
        )
    }

    private var memMetricCell: some View {
        ExperimentalMetricTile(
            label: "MEM %",
            percentage: isOnline ? percentageValue(stats?.memUsage) : nil,
            valueTint: palette.memoryAccent,
            trendValues: memTrendSeries,
            palette: palette
        )
    }

    private var networkMetricCell: some View {
        ExperimentalRateMetricColumn(
            topItem: downloadMetric,
            bottomItem: uploadMetric,
            accent: palette.rateAccent,
            palette: palette
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var diskMetricCell: some View {
        ExperimentalRateMetricColumn(
            topItem: diskReadMetric,
            bottomItem: diskWriteMetric,
            accent: palette.rateAccent,
            palette: palette
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var terminalButton: some View {
        Button(action: onOpenTerminal) {
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

    private var terminalButtonForeground: Color {
        isOnline ? palette.primaryText : palette.secondaryText
    }

    private var connectionFailedBadge: some View {
        Text("连接失败")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(Color(red: 0.82, green: 0.29, blue: 0.23))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(red: 0.82, green: 0.29, blue: 0.23).opacity(0.10))
            .clipShape(Capsule())
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

    private var cpuUsageTint: Color {
        guard let usage = stats?.cpuUsage, isOnline else {
            return palette.secondaryText
        }

        switch usage {
        case ..<0.20:
            return Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
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

    private var uploadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "network-upload", label: "TX", value: uploadSpeedText)
    }

    private var downloadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "network-download", label: "RX", value: downloadSpeedText)
    }

    private var diskReadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "disk-read", label: "RD", value: diskReadSpeedText)
    }

    private var diskWriteMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "disk-write", label: "WR", value: diskWriteSpeedText)
    }

    private func rateMetric(id: String, label: String, value: String) -> ExperimentalRateMetricDescriptor {
        let parts = ExperimentalRateParts(rawValue: value)
        let unitText = parts.unit.isEmpty ? "k/s" : parts.unit.lowercased()
        return ExperimentalRateMetricDescriptor(
            id: id,
            label: label,
            unitText: unitText,
            parts: parts
        )
    }

    private func percentageValue(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }

    private func temperatureText(for value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }

    private func metricTrendValues(history: [Double], fallback: Double?) -> [Double] {
        if !history.isEmpty {
            return history
        }

        guard let fallback else {
            return []
        }

        return [min(max(fallback, 0), 1)]
    }
}

private struct ExperimentalMetricTile: View {
    let label: String
    let percentage: Int?
    let valueTint: Color
    let trendValues: [Double]
    let palette: ExperimentalHomePalette

    private var displayColor: Color {
        percentage == nil ? palette.secondaryText.opacity(0.42) : valueTint
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Group {
                if let percentage {
                    Text("\(percentage)")
                        .contentTransition(.numericText(value: Double(percentage)))
                        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: percentage)
                } else {
                    Text("--")
                }
            }
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundColor(displayColor)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .frame(maxWidth: .infinity, alignment: .center)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText.opacity(0.88))
                .tracking(1.1)
                .padding(.top, -3)
                .frame(maxWidth: .infinity, alignment: .center)

            ExperimentalUsageTrendSparkline(
                values: trendValues,
                isActive: percentage != nil,
                palette: palette
            )
            .frame(width: 70, height: 28, alignment: .center)
            .padding(.top, 8)
        }
        .frame(width: 76)
        .frame(maxHeight: .infinity, alignment: .center)
        .opacity(percentage == nil ? 0.82 : 1)
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
                .contentTransition(.numericText())
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: value)
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
                .contentTransition(.numericText(value: parts.numericAmount ?? 0))
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: parts.numericAmount ?? -1)

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

private struct ExperimentalUsageTrendSparkline: View {
    let values: [Double]
    let isActive: Bool
    let palette: ExperimentalHomePalette

    private let minimumVisibleRange: Double = 0.12

    private var clampedValues: [Double] {
        values.map { min(max($0, 0), 1) }
    }

    private var normalizedValues: [Double] {
        guard let minValue = clampedValues.min(),
              let maxValue = clampedValues.max() else {
            return []
        }

        let range = maxValue - minValue
        let padding = max(0.015, (minimumVisibleRange - range) / 2)
        let lowerBound = max(0, minValue - padding)
        let upperBound = min(1, maxValue + padding)
        let effectiveRange = max(upperBound - lowerBound, 0.000_1)

        return clampedValues.map { value in
            min(max((value - lowerBound) / effectiveRange, 0), 1)
        }
    }

    private var lineColor: Color {
        isActive
            ? palette.secondaryText.opacity(0.88)
            : palette.secondaryText.opacity(0.24)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            if normalizedValues.count >= 2 {
                sparklinePath(in: size)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(
                            lineWidth: 1.45,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            } else if let singleValue = normalizedValues.first {
                Path { path in
                    let y = yPosition(for: singleValue, in: size)
                    path.move(to: CGPoint(x: 1, y: y))
                    path.addLine(to: CGPoint(x: max(size.width - 1, 1), y: y))
                }
                .stroke(
                    lineColor.opacity(0.45),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                )
            } else {
                Capsule()
                    .fill(palette.secondaryText.opacity(0.16))
                    .frame(width: max(size.width - 12, 12), height: 1.2)
                    .position(x: size.width / 2, y: size.height * 0.62)
            }
        }
    }

    private func sparklinePath(in size: CGSize) -> Path {
        let topInset: CGFloat = 1
        let bottomInset: CGFloat = 2
        let horizontalInset: CGFloat = 1
        let usableHeight = max(size.height - topInset - bottomInset, 1)
        let usableWidth = max(size.width - (horizontalInset * 2), 1)
        let stepX = normalizedValues.count > 1
            ? usableWidth / CGFloat(normalizedValues.count - 1)
            : 0

        var path = Path()

        for (index, value) in normalizedValues.enumerated() {
            let point = CGPoint(
                x: horizontalInset + (CGFloat(index) * stepX),
                y: topInset + ((1 - CGFloat(value)) * usableHeight)
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func yPosition(for value: Double, in size: CGSize) -> CGFloat {
        let topInset: CGFloat = 1
        let bottomInset: CGFloat = 2
        let usableHeight = max(size.height - topInset - bottomInset, 1)
        return topInset + ((1 - CGFloat(value)) * usableHeight)
    }
}

private struct ExperimentalRateMetricDescriptor: Identifiable {
    let id: String
    let label: String
    let unitText: String
    let parts: ExperimentalRateParts
}

private struct ExperimentalRateMetricColumn: View {
    let topItem: ExperimentalRateMetricDescriptor
    let bottomItem: ExperimentalRateMetricDescriptor
    let accent: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            ExperimentalRateMetric(
                item: topItem,
                accent: accent,
                palette: palette
            )

            ExperimentalRateMetric(
                item: bottomItem,
                accent: accent,
                palette: palette
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ExperimentalRateMetric: View {
    let item: ExperimentalRateMetricDescriptor
    let accent: Color
    let palette: ExperimentalHomePalette

    private var isActive: Bool {
        item.parts.hasRenderableValue
    }

    private var valueColor: Color {
        isActive ? accent : palette.secondaryText.opacity(0.62)
    }

    private var metaColor: Color {
        palette.secondaryText.opacity(0.86)
    }

    var body: some View {
        VStack(alignment: .center, spacing: -2) {
            Text(item.parts.displayNumber)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .contentTransition(.numericText(value: item.parts.numericAmount ?? 0))
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: item.parts.numericAmount ?? -1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("\(item.label) \(item.unitText)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(metaColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ExperimentalHeaderBadge: View {
    let symbol: String
    let value: String
    let palette: ExperimentalHomePalette
    var tint: Color? = nil

    private var resolvedColor: Color {
        (tint ?? palette.secondaryText).opacity(0.68)
    }

    var body: some View {
        HStack(spacing: 5) {
            ExperimentalHeaderSymbol(
                symbol: symbol,
                color: resolvedColor
            )

            Text(value)
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(resolvedColor)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
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
                    .font(.system(size: 12, weight: .regular))
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
            simplePins

            RoundedRectangle(cornerRadius: 2.6, style: .continuous)
                .stroke(color.opacity(0.82), lineWidth: 1.25)
                .frame(width: 10.4, height: 10.4)

            RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                .stroke(color.opacity(0.76), lineWidth: 0.9)
                .frame(width: 4.6, height: 4.6)
        }
        .frame(width: 16, height: 16)
    }

    private var simplePins: some View {
        ZStack {
            HStack(spacing: 1.9) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                        .fill(color.opacity(0.82))
                        .frame(width: 1.05, height: 2.0)
                }
            }
            .offset(y: -5.95)

            HStack(spacing: 1.9) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                        .fill(color.opacity(0.82))
                        .frame(width: 1.05, height: 2.0)
                }
            }
            .offset(y: 5.95)

            VStack(spacing: 1.9) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                        .fill(color.opacity(0.82))
                        .frame(width: 2.0, height: 1.05)
                }
            }
            .offset(x: -5.95)

            VStack(spacing: 1.9) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 0.4, style: .continuous)
                        .fill(color.opacity(0.82))
                        .frame(width: 2.0, height: 1.05)
                }
            }
            .offset(x: 5.95)
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

        if abs(amount) < 0.000_1 {
            return "0"
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
    let rateAccent: Color
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
                memoryAccent: Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0),
                rateAccent: Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0),
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
                memoryAccent: Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0),
                rateAccent: Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0),
                metaTint: Color(red: 0.29, green: 0.47, blue: 0.88),
                cardShadow: Color.black.opacity(0.16)
            )
        @unknown default:
            return palette(for: .dark)
        }
    }
}
