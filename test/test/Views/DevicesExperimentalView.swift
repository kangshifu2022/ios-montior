import SwiftUI
import UniformTypeIdentifiers

struct DevicesExperimentalView: View {
    @ObservedObject var store: ServerStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ExperimentalHomeTheme.storageKey) private var experimentalHomeThemeRawValue = ExperimentalHomeTheme.system.rawValue
    @AppStorage(ExperimentalHomeCardView.storageKey) private var experimentalHomeCardViewRawValue = ExperimentalHomeCardView.detailed.rawValue
    @State private var selectedServer: ServerConfig?
    @State private var terminalServer: ServerConfig?
    @State private var editingServer: ServerConfig?
    @State private var draggedServerID: UUID?
    @State private var expandedServerIDsInCompactMode: Set<UUID> = []

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
            .navigationDestination(item: $selectedServer) { config in
                DeviceDetailView(config: config, store: store)
            }
            .sheet(item: $editingServer) { server in
                AddServerView(store: store, editingServer: server)
            }
            .fullScreenCover(item: $terminalServer) { config in
                TerminalView(server: config)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                ExperimentalViewToggleIcon(
                    mode: homeCardView,
                    color: palette.primaryText
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleHomeCardView()
                }
                .accessibilityLabel(homeCardView == .detailed ? "切换到缩略视图" : "切换到详细视图")
                .accessibilityAddTraits(.isButton)
            }

            Text("概览")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundColor(palette.primaryText)
                .tracking(-0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func reorderableCard(for server: ServerConfig) -> some View {
        let serverID = server.id
        let draggedServerIDBinding = $draggedServerID
        let isDragged = draggedServerID == serverID
        let isCollapsed = store.isCollapsed(server.id)
        let isExpandedInCompactMode = expandedServerIDsInCompactMode.contains(server.id)
        let showsDetailedCard = homeCardView == .detailed ? !isCollapsed : isExpandedInCompactMode

        Group {
            if showsDetailedCard {
                ExperimentalServerCard(
                    config: server,
                    stats: store.stats(for: server),
                    palette: palette
                ) {
                    selectedServer = server
                } onToggleCollapse: {
                    toggleCardExpansion(for: server.id)
                } onOpenTerminal: {
                    terminalServer = server
                }
            } else {
                ExperimentalCompactServerCard(
                    config: server,
                    stats: store.stats(for: server),
                    palette: palette,
                    showsExpandControl: true
                ) {
                    selectedServer = server
                } onToggleCollapse: {
                    toggleCardExpansion(for: server.id)
                }
            }
        }
        .scaleEffect(isDragged ? 1.02 : 1)
        .shadow(color: isDragged ? palette.cardShadow.opacity(1.2) : .clear, radius: 16, x: 0, y: 10)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isDragged)
        .onDrag {
            draggedServerID = serverID
            return ExperimentalServerDragItemProvider(serverID: serverID) {
                guard draggedServerIDBinding.wrappedValue == serverID else {
                    return
                }
                draggedServerIDBinding.wrappedValue = nil
            }
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

    private func toggleHomeCardView() {
        let nextMode: ExperimentalHomeCardView = homeCardView == .detailed ? .compact : .detailed
        experimentalHomeCardViewRawValue = nextMode.rawValue
        expandedServerIDsInCompactMode.removeAll()

        let shouldCollapseAllCards = nextMode == .compact
        for server in store.servers {
            store.setCollapsed(shouldCollapseAllCards, for: server.id)
        }
    }

    private func toggleCardExpansion(for serverID: UUID) {
        if homeCardView == .compact {
            if expandedServerIDsInCompactMode.contains(serverID) {
                expandedServerIDsInCompactMode.remove(serverID)
            } else {
                expandedServerIDsInCompactMode.insert(serverID)
            }
            return
        }

        store.toggleCollapsed(serverID)
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

private final class ExperimentalServerDragItemProvider: NSItemProvider {
    private let onDragEnded: () -> Void

    init(serverID: UUID, onDragEnded: @escaping () -> Void) {
        self.onDragEnded = onDragEnded
        super.init(object: serverID.uuidString as NSString)
    }

    deinit {
        DispatchQueue.main.async { [onDragEnded] in
            onDragEnded()
        }
    }
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
    let showsExpandControl: Bool
    let onOpenDetail: () -> Void
    let onToggleCollapse: () -> Void

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

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Text(headerDisplayName)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if showsExpandControl {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(palette.secondaryText.opacity(0.9))
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
            if showsExpandControl {
                onToggleCollapse()
            } else {
                onOpenDetail()
            }
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
        .shadow(color: palette.cardShadow, radius: 14, x: 0, y: 8)
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
    let onToggleCollapse: () -> Void
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
        .shadow(color: palette.cardShadow, radius: 20, x: 0, y: 10)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleCollapse) {
                HStack(spacing: 6) {
                    Text(headerDisplayName)
                        .font(.system(size: 19, weight: .light, design: .rounded))
                        .foregroundColor(palette.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(palette.secondaryText.opacity(0.92))
                }
            }
            .buttonStyle(.plain)

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
        HStack(alignment: .center, spacing: 10) {
            cpuMetricCell
            memMetricCell

            ExperimentalRateMetricColumn(
                topItem: uploadMetric,
                bottomItem: downloadMetric,
                accent: palette.memoryAccent,
                palette: palette
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            ExperimentalRateMetricColumn(
                topItem: diskReadMetric,
                bottomItem: diskWriteMetric,
                accent: palette.memoryAccent,
                palette: palette
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84, alignment: .leading)
    }

    private var cpuMetricCell: some View {
        ExperimentalMetricTile(
            label: "CPU %",
            percentage: isOnline ? percentageValue(stats?.cpuUsage) : nil,
            valueTint: cpuUsageTint,
            ringStyle: .standard,
            palette: palette
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var memMetricCell: some View {
        ExperimentalMetricTile(
            label: "MEM %",
            percentage: isOnline ? percentageValue(stats?.memUsage) : nil,
            valueTint: palette.memoryAccent,
            ringStyle: .memoryGradient,
            palette: palette
        )
        .frame(maxWidth: .infinity, alignment: .center)
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

    private var uploadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "network-upload", label: "upload", value: uploadSpeedText)
    }

    private var downloadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "network-download", label: "down", value: downloadSpeedText)
    }

    private var diskReadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "disk-read", label: "read", value: diskReadSpeedText)
    }

    private var diskWriteMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "disk-write", label: "write", value: diskWriteSpeedText)
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

    private let gapAngle: Double = 130
    private let ringLineWidth: CGFloat = 6

    private var normalizedValue: Double {
        Double(min(max(percentage ?? 0, 0), 100)) / 100
    }

    private var arcSweepAngle: Double {
        360 - gapAngle
    }

    private var arcStartAngle: Double {
        90 + (gapAngle / 2)
    }

    private var arcEndAngle: Double {
        arcStartAngle + arcSweepAngle
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
        StrokeStyle(lineWidth: ringLineWidth, lineCap: ringStyle == .memoryGradient ? .round : .butt)
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

    var body: some View {
        ZStack {
            if ringStyle == .memoryGradient {
                ExperimentalRingArc(
                    startAngle: arcStartAngle,
                    endAngle: arcEndAngle,
                    inset: ringLineWidth / 2
                )
                .stroke(trackColor, lineWidth: ringLineWidth)

                if normalizedValue > 0 {
                    ExperimentalRingArc(
                        startAngle: arcStartAngle,
                        endAngle: arcStartAngle + (arcSweepAngle * normalizedValue),
                        inset: ringLineWidth / 2
                    )
                    .stroke(activeStroke, style: activeStrokeStyle)
                }

                ExperimentalRingArc(
                    startAngle: arcStartAngle,
                    endAngle: arcEndAngle,
                    inset: ringLineWidth / 2
                )
                .stroke(
                    palette.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03),
                    lineWidth: 1
                )
                .padding(-5)
            } else {
                ExperimentalRingArc(
                    startAngle: arcStartAngle,
                    endAngle: arcEndAngle,
                    inset: ringLineWidth / 2
                )
                .stroke(trackColor, lineWidth: ringLineWidth)

                if normalizedValue > 0 {
                    ExperimentalRingArc(
                        startAngle: arcStartAngle,
                        endAngle: arcStartAngle + (arcSweepAngle * normalizedValue),
                        inset: ringLineWidth / 2
                    )
                    .stroke(activeStroke, style: activeStrokeStyle)
                }
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

private struct ExperimentalRingArc: Shape {
    var startAngle: Double
    var endAngle: Double
    let inset: CGFloat

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(startAngle, endAngle) }
        set {
            startAngle = newValue.first
            endAngle = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let radius = max(0, (min(rect.width, rect.height) / 2) - inset)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let segmentCount = max(2, Int(abs(endAngle - startAngle) / 4))
        let angles = stride(from: 0, through: segmentCount, by: 1).map { index in
            startAngle + ((endAngle - startAngle) * Double(index) / Double(segmentCount))
        }

        var path = Path()
        for (index, angle) in angles.enumerated() {
            let radians = angle * .pi / 180
            let point = CGPoint(
                x: center.x + CGFloat(cos(radians)) * radius,
                y: center.y + CGFloat(sin(radians)) * radius
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
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
        VStack(alignment: .leading, spacing: 12) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        palette.secondaryText.opacity(0.88)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(item.parts.displayNumber)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundColor(valueColor)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(minWidth: 32, alignment: .trailing)

            VStack(alignment: .leading, spacing: -1) {
                Text(item.unitText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(metaColor)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(item.label)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(metaColor)
                    .lineLimit(1)
            }
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
