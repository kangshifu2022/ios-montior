import SwiftUI
import UniformTypeIdentifiers

struct DevicesExperimentalView: View {
    fileprivate static let cardGroupIndicatorWidth: CGFloat = 2.5
    fileprivate static let cardGroupIndicatorHeight: CGFloat = 11
    fileprivate static let detailedCardTopPadding: CGFloat = 12
    fileprivate static let detailedCardCornerRadius: CGFloat = 25

    @ObservedObject var store: ServerStore
    @EnvironmentObject private var terminalWorkspace: TerminalWorkspace
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ExperimentalHomeTheme.storageKey) private var experimentalHomeThemeRawValue = ExperimentalHomeTheme.system.rawValue
    @AppStorage(ExperimentalHomeCardView.storageKey) private var experimentalHomeCardViewRawValue = ExperimentalHomeCardView.detailed.rawValue
    @State private var selectedServer: ServerConfig?
    @State private var editingServer: ServerConfig?
    @State private var pendingDeletionServer: ServerConfig?
    @State private var selectedGroupName = ServerConfig.allGroupName
    @State private var showsExpandedGroupTags = false
    @State private var draggedServerID: UUID?

    private struct HomeLayout {
        let usesTwoColumnCards: Bool
        let hidesTabBar: Bool
        let cardSpacing: CGFloat
        let cardColumns: [GridItem]
    }

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

    private var appBuildNumber: String {
        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           !build.isEmpty {
            return build
        }

        if let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? NSNumber {
            return build.stringValue
        }

        return "--"
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
        guard showsExpandedGroupTags else {
            return ServerConfig.allGroupName
        }

        return availableGroupNames.contains(selectedGroupName) ? selectedGroupName : ServerConfig.allGroupName
    }

    private var visibleGroupNames: [String] {
        showsExpandedGroupTags ? availableGroupNames : [ServerConfig.allGroupName]
    }

    private var filteredServers: [ServerConfig] {
        guard activeGroupName != ServerConfig.allGroupName else {
            return store.servers
        }

        return store.servers.filter { $0.resolvedGroupName == activeGroupName }
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = homeLayout(for: proxy.size)

            NavigationStack {
                ZStack(alignment: .topTrailing) {
                    palette.pageBackground
                        .ignoresSafeArea()

                    ScrollView {
                        VStack(spacing: 18) {
                            pageHeader

                            if store.servers.isEmpty {
                                emptyState
                            } else {
                                cardsSection(layout: layout)
                                    .animation(.spring(response: 0.28, dampingFraction: 0.84), value: filteredServers)
                                    .onDrop(of: [UTType.text], delegate: ExperimentalServerListDropDelegate(draggedServerID: $draggedServerID))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                    }
                    .refreshable {
                        await store.refreshAllIfNeeded(forceDynamic: true, forceStatic: true)
                    }
                    homeCardViewToggleButton
                        .padding(.top, 12)
                        .padding(.trailing, 16)
                        .zIndex(1)
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(item: $selectedServer) { config in
                    DeviceDetailView(config: config, store: store)
                }
                .sheet(item: $editingServer) { server in
                    AddServerView(store: store, editingServer: server)
                }
                .alert("删除设备", isPresented: deleteConfirmationPresented) {
                    Button("删除", role: .destructive) {
                        confirmDeletePendingServer()
                    }

                    Button("取消", role: .cancel) {
                        pendingDeletionServer = nil
                    }
                } message: {
                    Text("确认删除“\(pendingDeletionServerDisplayName)”？删除后会移除这台设备的配置、监控缓存和本地终端会话数据。")
                }
                .fullScreenCover(item: $terminalWorkspace.presentedSession) { session in
                    TerminalSessionHostView(
                        server: session.server,
                        viewModel: session.viewModel,
                        onSuspend: {
                            terminalWorkspace.suspend(session)
                        },
                        onClose: {
                            terminalWorkspace.close(session)
                        }
                    )
                }
                .onChange(of: selectedServer?.id) { _, _ in
                    draggedServerID = nil
                }
                .onChange(of: editingServer?.id) { _, _ in
                    draggedServerID = nil
                }
                .onChange(of: terminalWorkspace.presentedSession?.id) { _, _ in
                    draggedServerID = nil
                }
                .task(id: store.servers.map(\.id)) {
                    await triggerHomeRefresh()

                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard !Task.isCancelled else { break }
                        await triggerHomeRefresh(forceDynamic: true)
                    }
                }
                .onDisappear {
                    draggedServerID = nil
                }
                .toolbar(layout.hidesTabBar ? .hidden : .visible, for: .tabBar)
            }
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private func homeLayout(for size: CGSize) -> HomeLayout {
        let usesLandscapeMonitorMode = size.width > size.height
        let cardSpacing = homeCardView == .detailed ? 20.0 : 10.0
        let cardColumns: [GridItem]

        if usesLandscapeMonitorMode {
            cardColumns = [
                GridItem(.flexible(), spacing: 16, alignment: .top),
                GridItem(.flexible(), spacing: 16, alignment: .top)
            ]
        } else {
            cardColumns = [
                GridItem(.flexible(), spacing: 0, alignment: .top)
            ]
        }

        return HomeLayout(
            usesTwoColumnCards: usesLandscapeMonitorMode,
            hidesTabBar: usesLandscapeMonitorMode,
            cardSpacing: cardSpacing,
            cardColumns: cardColumns
        )
    }

    @ViewBuilder
    private func cardsSection(layout: HomeLayout) -> some View {
        if layout.usesTwoColumnCards {
            LazyVGrid(columns: layout.cardColumns, alignment: .leading, spacing: layout.cardSpacing) {
                ForEach(filteredServers) { server in
                    reorderableCard(for: server)
                }
            }
        } else {
            LazyVStack(spacing: layout.cardSpacing) {
                ForEach(filteredServers) { server in
                    reorderableCard(for: server)
                }
            }
        }
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer(minLength: 0)
            }
            .frame(height: 30)

            HStack(alignment: .top, spacing: 3) {
                Text("概览")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .foregroundColor(palette.primaryText)
                    .tracking(-0.6)

                buildLabel
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !availableGroupNames.isEmpty {
                groupTabs
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var homeCardViewToggleButton: some View {
        Menu {
            Button(action: toggleHomeCardView) {
                Label(homeCardViewMenuPrimaryActionTitle, systemImage: homeCardViewMenuPrimaryActionIconName)
            }

            Button(action: { sortServersByName(ascending: true) }) {
                Label("A-Z", systemImage: "arrow.up")
            }

            Button(action: { sortServersByName(ascending: false) }) {
                Label("Z-A", systemImage: "arrow.down")
            }

            Button(action: { sortServersByCreatedAt(ascending: false) }) {
                Label("newest to oldest", systemImage: "arrow.down.circle")
            }

            Button(action: { sortServersByCreatedAt(ascending: true) }) {
                Label("oldest to newest", systemImage: "arrow.up.circle")
            }
        } label: {
            Image(systemName: homeCardViewToggleIconName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(palette.primaryText)
        .accessibilityLabel("视图与排序")
    }

    private var homeCardViewToggleIconName: String {
        "square.grid.2x2"
    }

    private var buildLabel: some View {
        Text("build\(appBuildNumber)")
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(palette.secondaryText.opacity(0.92))
            .padding(.top, 4)
            .accessibilityLabel("构建号 \(appBuildNumber)")
    }

    private var homeCardViewMenuPrimaryActionTitle: String {
        switch homeCardView {
        case .detailed:
            return "切换为列表模式"
        case .compact:
            return "切换为卡片模式"
        }
    }

    private var homeCardViewMenuPrimaryActionIconName: String {
        switch homeCardView {
        case .detailed:
            return "list.bullet"
        case .compact:
            return "square.grid.2x2"
        }
    }

    private var groupTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleGroupNames, id: \.self) { groupName in
                    let isSelected = isGroupTagHighlighted(groupName)
                    let groupAccentColor = ExperimentalGroupAccentPalette.color(for: groupName)
                    groupTabButton(
                        groupName: groupName,
                        isSelected: isSelected,
                        groupAccentColor: groupAccentColor
                    )
                }
            }
            .padding(.vertical, 0)
        }
    }

    @ViewBuilder
    private func groupTabButton(
        groupName: String,
        isSelected: Bool,
        groupAccentColor: Color?
    ) -> some View {
        Button {
            handleGroupTagTap(groupName)
        } label: {
            groupTabLabel(
                groupName: groupName,
                isSelected: isSelected,
                groupAccentColor: groupAccentColor
            )
        }
        .buttonStyle(.plain)
    }

    private func groupTabLabel(
        groupName: String,
        isSelected: Bool,
        groupAccentColor: Color?
    ) -> some View {
        HStack(spacing: 4) {
            if let groupAccentColor {
                ExperimentalGroupIndicatorLine(
                    color: groupAccentColor,
                    width: 2.5,
                    height: 8
                )
            }

            Text(groupName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(isSelected ? selectedGroupTabTextColor : palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(
            Capsule()
                .fill(isSelected ? selectedGroupTabBackground : groupTabBackground)
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? selectedGroupTabBorderColor : palette.cardBorder, lineWidth: 1)
        )
    }

    private func handleGroupTagTap(_ groupName: String) {
        if groupName == ServerConfig.allGroupName {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                selectedGroupName = ServerConfig.allGroupName
                showsExpandedGroupTags.toggle()
            }
            return
        }

        guard selectedGroupName != groupName else { return }
        selectedGroupName = groupName
    }

    private func isGroupTagHighlighted(_ groupName: String) -> Bool {
        if groupName == ServerConfig.allGroupName {
            return activeGroupName == ServerConfig.allGroupName
        }

        return groupName == activeGroupName
    }

    private var selectedGroupTabBackground: Color {
        palette.cardBackground
    }

    private var selectedGroupTabTextColor: Color {
        palette.primaryText
    }

    private var selectedGroupTabBorderColor: Color {
        palette.isDark ? Color.white.opacity(0.26) : Color.black.opacity(0.12)
    }

    private var groupTabBackground: Color {
        palette.isDark ? Color.white.opacity(0.06) : Color.white.opacity(0.82)
    }

    private func triggerHomeRefresh(
        forceDynamic: Bool = false,
        forceStatic: Bool = false
    ) async {
        await store.refreshAllIfNeeded(
            forceDynamic: forceDynamic,
            forceStatic: forceStatic
        )
    }

    @ViewBuilder
    private func reorderableCard(for server: ServerConfig) -> some View {
        let serverID = server.id
        let stats = store.stats(for: server)
        let cpuTrendValues = store.cpuUsageHistory(for: serverID)
        let memTrendValues = store.memUsageHistory(for: serverID)
        let hasSuspendedTerminal = terminalWorkspace.hasSuspendedSession(forServerID: serverID)
        let isDragged = draggedServerID == serverID
        let showsDetailedCard = homeCardView == .detailed

        Group {
            if showsDetailedCard {
                ExperimentalServerCard(
                    config: server,
                    stats: stats,
                    cpuTrendValues: cpuTrendValues,
                    memTrendValues: memTrendValues,
                    hasSuspendedTerminal: hasSuspendedTerminal,
                    palette: palette
                ) {
                    selectedServer = server
                } onOpenTerminal: {
                    terminalWorkspace.presentTerminal(for: server)
                }
            } else {
                ExperimentalCompactServerCard(
                    config: server,
                    stats: stats,
                    hasSuspendedTerminal: hasSuspendedTerminal,
                    palette: palette
                ) {
                    selectedServer = server
                } onOpenTerminal: {
                    terminalWorkspace.presentTerminal(for: server)
                }
            }
        }
        .contextMenu {
            Button {
                editingServer = server
            } label: {
                Label("编辑", systemImage: "square.and.pencil")
            }

            Button(role: .destructive) {
                pendingDeletionServer = server
            } label: {
                Label("删除", systemImage: "trash")
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
    }

    private func setHomeCardView(_ nextMode: ExperimentalHomeCardView) {
        experimentalHomeCardViewRawValue = nextMode.rawValue
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletionServer != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletionServer = nil
                }
            }
        )
    }

    private var pendingDeletionServerDisplayName: String {
        guard let pendingDeletionServer else {
            return "这台设备"
        }

        let trimmedName = pendingDeletionServer.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        return pendingDeletionServer.host
    }

    private func confirmDeletePendingServer() {
        guard let pendingDeletionServer else { return }
        terminalWorkspace.closeSessions(forServerID: pendingDeletionServer.id)
        TerminalPersistenceStore.removeSessions(for: pendingDeletionServer.id)
        store.deleteServer(id: pendingDeletionServer.id)
        self.pendingDeletionServer = nil
    }

    private func toggleHomeCardView() {
        let nextMode: ExperimentalHomeCardView = homeCardView == .detailed ? .compact : .detailed
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            setHomeCardView(nextMode)
        }
    }

    private func sortServersByName(ascending: Bool) {
        draggedServerID = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            store.sortServersByName(ascending: ascending)
        }
    }

    private func sortServersByCreatedAt(ascending: Bool) {
        draggedServerID = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
            store.sortServersByCreatedAt(ascending: ascending)
        }
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
            RoundedRectangle(cornerRadius: DevicesExperimentalView.detailedCardCornerRadius, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DevicesExperimentalView.detailedCardCornerRadius, style: .continuous))
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

private let suspendedTerminalAccentColor = Color(
    red: 48.0 / 255.0,
    green: 209.0 / 255.0,
    blue: 88.0 / 255.0
)

private struct ExperimentalCompactServerCard: View {
    let config: ServerConfig
    let stats: ServerStats?
    let hasSuspendedTerminal: Bool
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

    private var memTint: Color {
        usageTint(for: stats?.memUsage)
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
                        accent: memTint,
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

            terminalButton
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
        ExperimentalConnectionFailureBadge(palette: palette)
    }

    private var terminalButton: some View {
        Button(action: onOpenTerminal) {
            Image(systemName: "terminal")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(terminalButtonForeground)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(!isOnline && !hasSuspendedTerminal)
        .opacity(isOnline || hasSuspendedTerminal ? 1 : 0.45)
        .accessibilityLabel(hasSuspendedTerminal ? "恢复挂起终端" : "打开终端")
    }

    private var terminalButtonForeground: Color {
        if hasSuspendedTerminal {
            return suspendedTerminalAccentColor
        }
        return isOnline ? palette.primaryText : palette.secondaryText
    }

    private func percentageText(_ value: Double?) -> String {
        guard let value else {
            return "--"
        }
        return "\(Int((min(max(value, 0), 1) * 100).rounded()))"
    }

    private func cpuUsageTint(for value: Double?) -> Color {
        usageTint(for: value)
    }

    private func usageTint(for value: Double?) -> Color {
        guard let value else {
            return palette.secondaryText
        }

        switch value {
        case ..<0.50:
            return Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
        case ..<0.60:
            return Color(red: 0.53, green: 0.82, blue: 0.18)
        case ..<0.70:
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
    let hasSuspendedTerminal: Bool
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
        .padding(.top, DevicesExperimentalView.detailedCardTopPadding)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: DevicesExperimentalView.detailedCardCornerRadius, style: .continuous)
                .stroke(palette.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DevicesExperimentalView.detailedCardCornerRadius, style: .continuous))
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
            percentage: displayedPercentageValue(stats?.cpuUsage),
            isActive: isOnline && stats?.cpuUsage != nil,
            valueTint: cpuUsageTint,
            trendValues: cpuTrendSeries,
            sparklineYAxisMode: .adaptive,
            palette: palette
        )
    }

    private var memMetricCell: some View {
        ExperimentalMemoryFlipTile(
            percentage: displayedPercentageValue(stats?.memUsage),
            isActive: isOnline && stats?.memUsage != nil,
            valueTint: memUsageTint,
            trendValues: memTrendSeries,
            palette: palette,
            usedMegabytes: usedMemoryMegabytes,
            totalMegabytes: totalMemoryMegabytes
        )
    }

    private var networkMetricCell: some View {
        ExperimentalRateMetricColumn(
            topItem: uploadMetric,
            bottomItem: downloadMetric,
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
        .disabled(!isOnline && !hasSuspendedTerminal)
        .opacity(isOnline || hasSuspendedTerminal ? 1 : 0.45)
        .accessibilityLabel(hasSuspendedTerminal ? "恢复挂起终端" : "打开终端")
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
        if hasSuspendedTerminal {
            return suspendedTerminalAccentColor
        }
        return isOnline ? palette.primaryText : palette.secondaryText
    }

    private var connectionFailedBadge: some View {
        ExperimentalConnectionFailureBadge(palette: palette)
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
        usageTint(for: stats?.cpuUsage)
    }

    private var memUsageTint: Color {
        usageTint(for: stats?.memUsage)
    }

    private var usedMemoryMegabytes: Int {
        guard let stats, stats.memTotal > 0 else {
            return 0
        }
        return max(stats.memTotal - stats.memAvailable, 0)
    }

    private var totalMemoryMegabytes: Int {
        guard let stats, stats.memTotal > 0 else {
            return 0
        }
        return stats.memTotal
    }

    private func usageTint(for value: Double?) -> Color {
        guard let value, isOnline else {
            return palette.secondaryText
        }

        switch value {
        case ..<0.50:
            return Color(red: 48.0 / 255.0, green: 209.0 / 255.0, blue: 88.0 / 255.0)
        case ..<0.60:
            return Color(red: 0.53, green: 0.82, blue: 0.18)
        case ..<0.70:
            return Color(red: 0.95, green: 0.78, blue: 0.18)
        case ..<0.80:
            return Color(red: 0.96, green: 0.52, blue: 0.20)
        default:
            return Color(red: 0.90, green: 0.26, blue: 0.24)
        }
    }

    private var uploadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "network-upload", label: "↑", value: uploadSpeedText)
    }

    private var downloadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "network-download", label: "↓", value: downloadSpeedText)
    }

    private var diskReadMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "disk-read", label: "r", value: diskReadSpeedText)
    }

    private var diskWriteMetric: ExperimentalRateMetricDescriptor {
        rateMetric(id: "disk-write", label: "w", value: diskWriteSpeedText)
    }

    private func rateMetric(id: String, label: String, value: String) -> ExperimentalRateMetricDescriptor {
        let parts = ExperimentalRateParts(rawValue: value)
        return ExperimentalRateMetricDescriptor(
            id: id,
            label: label,
            parts: parts
        )
    }

    private func percentageValue(_ value: Double?) -> Int? {
        guard let value else { return nil }
        return Int((min(max(value, 0), 1) * 100).rounded())
    }

    private func displayedPercentageValue(_ value: Double?) -> Int {
        percentageValue(value) ?? 0
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
    let percentage: Int
    let isActive: Bool
    let valueTint: Color
    let trendValues: [Double]
    let sparklineYAxisMode: ExperimentalUsageTrendSparkline.YAxisMode
    let palette: ExperimentalHomePalette

    private var displayColor: Color {
        isActive ? valueTint : palette.secondaryText.opacity(0.42)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Text("\(percentage)")
                .contentTransition(.numericText(value: Double(percentage)))
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: percentage)
            .font(.system(size: 20, weight: .medium, design: .rounded))
            .foregroundColor(displayColor)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .frame(maxWidth: .infinity, alignment: .center)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(palette.secondaryText.opacity(0.88))
                .tracking(0.55)
                .padding(.top, -3)
                .frame(maxWidth: .infinity, alignment: .center)

            ExperimentalUsageTrendSparkline(
                values: trendValues,
                isActive: isActive,
                accent: valueTint,
                yAxisMode: sparklineYAxisMode,
                palette: palette
            )
            .frame(width: 70, height: 28, alignment: .center)
            .padding(.top, 8)
        }
        .frame(width: 76)
        .frame(maxHeight: .infinity, alignment: .center)
        .opacity(isActive ? 1 : 0.82)
    }
}

private struct ExperimentalMemoryFlipTile: View {
    let percentage: Int
    let isActive: Bool
    let valueTint: Color
    let trendValues: [Double]
    let palette: ExperimentalHomePalette
    let usedMegabytes: Int
    let totalMegabytes: Int

    @State private var isShowingBreakdown = false

    private let flipAxis = (x: CGFloat(0), y: CGFloat(1), z: CGFloat(0))

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                isShowingBreakdown.toggle()
            }
        } label: {
            ZStack {
                frontFace
                    .opacity(isShowingBreakdown ? 0 : 1)
                    .rotation3DEffect(.degrees(isShowingBreakdown ? 180 : 0), axis: flipAxis)

                backFace
                    .opacity(isShowingBreakdown ? 1 : 0)
                    .rotation3DEffect(.degrees(isShowingBreakdown ? 0 : -180), axis: flipAxis)
            }
            .frame(width: 76)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(isShowingBreakdown ? "显示内存占用率" : "显示内存已用和总量")
        .accessibilityHint("点击翻转内存卡片")
    }

    private var frontFace: some View {
        ExperimentalMetricTile(
            label: "MEM %",
            percentage: percentage,
            isActive: isActive,
            valueTint: valueTint,
            trendValues: trendValues,
            sparklineYAxisMode: .absolute,
            palette: palette
        )
    }

    private var backFace: some View {
        VStack(alignment: .center, spacing: 13) {
            ExperimentalMemoryBreakdownMetric(
                label: "used",
                megabytes: usedMegabytes,
                isActive: isActive,
                accent: valueTint,
                palette: palette
            )

            ExperimentalMemoryBreakdownMetric(
                label: "total",
                megabytes: totalMegabytes,
                isActive: isActive,
                accent: valueTint,
                palette: palette
            )
        }
        .frame(width: 76)
        .frame(maxHeight: .infinity, alignment: .center)
        .opacity(isActive ? 1 : 0.82)
    }
}

private struct ExperimentalMemoryBreakdownMetric: View {
    let label: String
    let megabytes: Int
    let isActive: Bool
    let accent: Color
    let palette: ExperimentalHomePalette

    private var display: ExperimentalCompactCapacityDisplay {
        ExperimentalCompactCapacityDisplay(megabytes: megabytes)
    }

    private var valueColor: Color {
        isActive && display.hasRenderableValue ? accent : palette.secondaryText.opacity(0.42)
    }

    private var metaColor: Color {
        palette.secondaryText.opacity(0.86)
    }

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(display.numberText)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(valueColor)
                    .monospacedDigit()
                    .tracking(-0.9)
                    .contentTransition(.numericText(value: display.animationValue))
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: display.animationValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if !display.compactUnitText.isEmpty {
                    Text(display.compactUnitText)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(metaColor)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundColor(metaColor)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ExperimentalCompactCapacityDisplay {
    let numberText: String
    let compactUnitText: String
    let animationValue: Double
    let hasRenderableValue: Bool

    init(megabytes: Int) {
        guard megabytes > 0 else {
            numberText = "--"
            compactUnitText = ""
            animationValue = 0
            hasRenderableValue = false
            return
        }

        hasRenderableValue = true
        if megabytes >= 1024 {
            let gigabytes = Double(megabytes) / 1024
            numberText = Self.displayText(from: gigabytes)
            compactUnitText = "G"
            animationValue = gigabytes
        } else {
            numberText = "\(megabytes)"
            compactUnitText = "M"
            animationValue = Double(megabytes)
        }
    }

    private static func displayText(from amount: Double) -> String {
        let roundedAmount = amount.rounded()
        if abs(amount - roundedAmount) < 0.05 {
            return String(Int(roundedAmount))
        }

        if amount < 10 {
            return String(format: "%.1f", amount)
        }

        return String(Int(amount.rounded()))
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
    enum YAxisMode {
        case adaptive
        case absolute
    }

    let values: [Double]
    let isActive: Bool
    let accent: Color
    let yAxisMode: YAxisMode
    let palette: ExperimentalHomePalette

    private let minimumVisibleRange: Double = 0.12

    private var clampedValues: [Double] {
        values.map { min(max($0, 0), 1) }
    }

    private var normalizedValues: [Double] {
        switch yAxisMode {
        case .adaptive:
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
        case .absolute:
            return clampedValues
        }
    }

    private var lineColor: Color {
        isActive
            ? accent
            : palette.secondaryText.opacity(0.24)
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                accent.opacity(palette.isDark ? 0.22 : 0.16),
                accent.opacity(palette.isDark ? 0.03 : 0.015)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            if !isActive {
                placeholderSparklinePath(in: size)
                    .stroke(
                        lineColor,
                        style: StrokeStyle(
                            lineWidth: 1.2,
                            lineCap: .round,
                            lineJoin: .round,
                            dash: [3.5, 3]
                        )
                    )
            } else if normalizedValues.count >= 2 {
                ZStack {
                    areaPath(in: size)
                        .fill(areaGradient)

                    sparklinePath(in: size)
                        .stroke(
                            lineColor,
                            style: StrokeStyle(
                                lineWidth: 1.45,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
            } else if let singleValue = normalizedValues.first {
                ZStack {
                    singleValueAreaPath(for: singleValue, in: size)
                        .fill(areaGradient.opacity(0.72))

                    Path { path in
                        let y = yPosition(for: singleValue, in: size)
                        path.move(to: CGPoint(x: 1, y: y))
                        path.addLine(to: CGPoint(x: max(size.width - 1, 1), y: y))
                    }
                    .stroke(
                        lineColor.opacity(0.45),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
                    )
                }
            } else {
                Capsule()
                    .fill(palette.secondaryText.opacity(0.16))
                    .frame(width: max(size.width - 12, 12), height: 1.2)
                    .position(x: size.width / 2, y: size.height * 0.62)
            }
        }
    }

    private func placeholderSparklinePath(in size: CGSize) -> Path {
        let topInset: CGFloat = 2
        let bottomInset: CGFloat = 3
        let horizontalInset: CGFloat = 1
        let usableHeight = max(size.height - topInset - bottomInset, 1)
        let usableWidth = max(size.width - (horizontalInset * 2), 1)
        let placeholderLevels: [CGFloat] = [0.64, 0.46, 0.58, 0.34, 0.49, 0.29]
        let stepX = placeholderLevels.count > 1
            ? usableWidth / CGFloat(placeholderLevels.count - 1)
            : 0

        var path = Path()

        for (index, level) in placeholderLevels.enumerated() {
            let point = CGPoint(
                x: horizontalInset + (CGFloat(index) * stepX),
                y: topInset + (level * usableHeight)
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func sparklinePath(in size: CGSize) -> Path {
        var path = Path()
        let points = sparklinePoints(in: size)

        for (index, point) in points.enumerated() {
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }

    private func areaPath(in size: CGSize) -> Path {
        let points = sparklinePoints(in: size)
        guard let firstPoint = points.first, let lastPoint = points.last else {
            return Path()
        }

        let baselineY = max(size.height - 2, firstPoint.y)
        var path = Path()
        path.move(to: CGPoint(x: firstPoint.x, y: baselineY))

        for point in points {
            path.addLine(to: point)
        }

        path.addLine(to: CGPoint(x: lastPoint.x, y: baselineY))
        path.closeSubpath()
        return path
    }

    private func singleValueAreaPath(for value: Double, in size: CGSize) -> Path {
        let y = yPosition(for: value, in: size)
        let startX: CGFloat = 1
        let endX = max(size.width - 1, 1)
        let baselineY = max(size.height - 2, y)
        var path = Path()
        path.move(to: CGPoint(x: startX, y: baselineY))
        path.addLine(to: CGPoint(x: startX, y: y))
        path.addLine(to: CGPoint(x: endX, y: y))
        path.addLine(to: CGPoint(x: endX, y: baselineY))
        path.closeSubpath()
        return path
    }

    private func sparklinePoints(in size: CGSize) -> [CGPoint] {
        let topInset: CGFloat = 1
        let bottomInset: CGFloat = 2
        let horizontalInset: CGFloat = 1
        let usableHeight = max(size.height - topInset - bottomInset, 1)
        let usableWidth = max(size.width - (horizontalInset * 2), 1)
        let stepX = normalizedValues.count > 1
            ? usableWidth / CGFloat(normalizedValues.count - 1)
            : 0

        return normalizedValues.enumerated().map { index, value in
            CGPoint(
                x: horizontalInset + (CGFloat(index) * stepX),
                y: topInset + ((1 - CGFloat(value)) * usableHeight)
            )
        }
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
    let parts: ExperimentalRateParts
}

private struct ExperimentalRateMetricColumn: View {
    let topItem: ExperimentalRateMetricDescriptor
    let bottomItem: ExperimentalRateMetricDescriptor
    let accent: Color
    let palette: ExperimentalHomePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct ExperimentalRateMetric: View {
    let item: ExperimentalRateMetricDescriptor
    let accent: Color
    let palette: ExperimentalHomePalette

    private var display: ExperimentalNormalizedRateDisplay {
        ExperimentalNormalizedRateDisplay(parts: item.parts)
    }

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
        VStack(alignment: .center, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(display.numberText)
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundColor(valueColor)
                    .monospacedDigit()
                    .tracking(-1.1)
                    .contentTransition(.numericText(value: display.animationValue))
                    .animation(.spring(response: 0.34, dampingFraction: 0.84), value: display.animationValue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                Text(display.compactUnitText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(metaColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(item.label)
                Text("/s")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundColor(metaColor)
            .monospacedDigit()
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ExperimentalNormalizedRateDisplay {
    let numberText: String
    let compactUnitText: String
    let animationValue: Double

    init(parts: ExperimentalRateParts) {
        let normalized = Self.normalizedAmount(
            amount: parts.numericAmount ?? 0,
            unit: parts.unit
        )
        numberText = parts.hasRenderableValue ? Self.displayText(from: normalized.amount) : "0"
        compactUnitText = Self.compactUnit(from: normalized.unit)
        animationValue = normalized.amount
    }

    private static func normalizedAmount(amount: Double, unit: String) -> (amount: Double, unit: String) {
        let normalizedUnit = unit.lowercased()

        switch normalizedUnit {
        case "k/s":
            if amount >= 1024 {
                return (amount / 1024, "m/s")
            }
            return (amount, "k/s")
        case "mb/s":
            return (amount, "m/s")
        case "gb/s":
            return (amount, "g/s")
        case "":
            return (amount, "k/s")
        default:
            return (amount, normalizedUnit)
        }
    }

    private static func compactUnit(from rawUnit: String) -> String {
        switch rawUnit.lowercased() {
        case "k/s":
            return "K"
        case "m/s", "mb/s":
            return "M"
        case "g/s", "gb/s":
            return "G"
        case "b/s":
            return "B"
        default:
            return rawUnit
                .replacingOccurrences(of: "/s", with: "")
                .uppercased()
        }
    }

    private static func displayText(from amount: Double) -> String {
        if abs(amount) < 0.000_1 {
            return "0"
        }

        let roundedAmount = Int(amount.rounded())
        if roundedAmount == 0, amount > 0 {
            return "1"
        }

        return String(roundedAmount)
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

private struct ExperimentalConnectionFailureBadge: View {
    let palette: ExperimentalHomePalette

    private var accentColor: Color {
        palette.offline.opacity(palette.isDark ? 0.94 : 0.98)
    }

    var body: some View {
        Image(systemName: "wifi.slash")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(accentColor)
            .frame(width: 28, height: 28)
            .background(accentColor.opacity(palette.isDark ? 0.14 : 0.10))
            .clipShape(Capsule())
            .accessibilityLabel("连接失败")
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
