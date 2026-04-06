import Foundation
import SwiftUI
import Combine

@MainActor
final class ServerStore: ObservableObject {
    private enum RefreshRequest: Sendable {
        case full(ServerConfig)
        case dynamic(ServerConfig)
    }

    private enum RefreshResult: Sendable {
        case full(UUID, ServerStats)
        case dynamic(UUID, ServerDynamicInfo)
    }

    @Published var servers: [ServerConfig] = []
    @Published private(set) var staticInfoByServerID: [UUID: ServerStaticInfo] = [:]
    @Published private(set) var dynamicInfoByServerID: [UUID: ServerDynamicInfo] = [:]
    @Published private(set) var refreshingServerIDs: Set<UUID> = []
    @Published private(set) var remoteAlertStatusByServerID: [UUID: RemoteAlertStatus] = [:]
    @Published private(set) var remoteAlertOperationServerIDs: Set<UUID> = []
    @Published private(set) var alertSettings = AlertSettings()
    @Published private(set) var collapsedServerIDs: Set<UUID> = []

    private let serversKey = "saved_servers"
    private let alertSettingsKey = "saved_alert_settings"
    private let staticInfoKey = "cached_server_static_info"
    private let dynamicInfoKey = "cached_server_dynamic_info"
    private let remoteAlertStatusKey = "cached_remote_alert_status"
    private let collapsedServerIDsKey = "collapsed_server_ids"
    private let legacyStatsKey = "cached_server_stats"
    private var lastStaticRefreshDates: [UUID: Date] = [:]
    private var lastDynamicRefreshDates: [UUID: Date] = [:]
    private var lastSuccessfulDynamicRefreshDates: [UUID: Date] = [:]
    private var consecutiveDynamicFailureCounts: [UUID: Int] = [:]
    private let staticRefreshInterval: TimeInterval = 60
    private let dynamicRefreshInterval: TimeInterval = 3
    private let offlineTransitionFailureThreshold = 2
    private let offlineTransitionGraceInterval: TimeInterval = 12
    private let autoCollapseFailureThreshold = 3
    private let maxDerivedMetricSampleAge: TimeInterval = 12
    private let refreshBatchStaggerInterval: TimeInterval = 0.18
    private let maxRefreshBatchStaggerSlots = 6

    init() {
        load()
        loadAlertSettings()
        loadCachedInfo()
    }

    func add(_ server: ServerConfig) {
        servers.append(server)
        save()
    }

    func update(_ server: ServerConfig) {
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
            staticInfoByServerID.removeValue(forKey: server.id)
            dynamicInfoByServerID.removeValue(forKey: server.id)
            remoteAlertStatusByServerID.removeValue(forKey: server.id)
            lastStaticRefreshDates.removeValue(forKey: server.id)
            lastDynamicRefreshDates.removeValue(forKey: server.id)
            lastSuccessfulDynamicRefreshDates.removeValue(forKey: server.id)
            consecutiveDynamicFailureCounts.removeValue(forKey: server.id)
            refreshingServerIDs.remove(server.id)
            remoteAlertOperationServerIDs.remove(server.id)
            save()
            saveCachedInfo()
        }
    }

    func delete(at offsets: IndexSet) {
        let deletedIDs = offsets.map { servers[$0].id }
        servers.remove(atOffsets: offsets)
        deletedIDs.forEach {
            staticInfoByServerID.removeValue(forKey: $0)
            dynamicInfoByServerID.removeValue(forKey: $0)
            remoteAlertStatusByServerID.removeValue(forKey: $0)
            lastStaticRefreshDates.removeValue(forKey: $0)
            lastDynamicRefreshDates.removeValue(forKey: $0)
            lastSuccessfulDynamicRefreshDates.removeValue(forKey: $0)
            consecutiveDynamicFailureCounts.removeValue(forKey: $0)
            refreshingServerIDs.remove($0)
            remoteAlertOperationServerIDs.remove($0)
            collapsedServerIDs.remove($0)
        }
        save()
        saveCollapsedServerIDs()
        saveCachedInfo()
    }

    func deleteServer(id: UUID) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            return
        }

        delete(at: IndexSet(integer: index))
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        servers.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func moveServer(id: UUID, to targetIndex: Int) {
        guard let sourceIndex = servers.firstIndex(where: { $0.id == id }) else {
            return
        }

        let boundedTarget = min(max(targetIndex, 0), servers.count - 1)
        guard sourceIndex != boundedTarget else {
            return
        }

        let destination = boundedTarget > sourceIndex ? boundedTarget + 1 : boundedTarget
        servers.move(fromOffsets: IndexSet(integer: sourceIndex), toOffset: destination)
        save()
    }

    func stats(for config: ServerConfig) -> ServerStats? {
        let staticInfo = staticInfoByServerID[config.id]
        let dynamicInfo = dynamicInfoByServerID[config.id]
        if staticInfo == nil && dynamicInfo == nil {
            return nil
        }
        return ServerStats(config: config, staticInfo: staticInfo, dynamicInfo: dynamicInfo)
    }

    func isRefreshing(_ id: UUID) -> Bool {
        refreshingServerIDs.contains(id)
    }

    func remoteAlertStatus(for config: ServerConfig) -> RemoteAlertStatus? {
        remoteAlertStatusByServerID[config.id]
    }

    func isCollapsed(_ id: UUID) -> Bool {
        collapsedServerIDs.contains(id)
    }

    func toggleCollapsed(_ id: UUID) {
        setCollapsed(!collapsedServerIDs.contains(id), for: id)
    }

    func setCollapsed(_ isCollapsed: Bool, for id: UUID) {
        if isCollapsed {
            collapsedServerIDs.insert(id)
        } else {
            collapsedServerIDs.remove(id)
        }
        saveCollapsedServerIDs()
    }

    func isPerformingRemoteAlertAction(_ id: UUID) -> Bool {
        remoteAlertOperationServerIDs.contains(id)
    }

    func updateAlertSettings(
        for id: UUID,
        alertConfiguration: AlertConfiguration
    ) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else {
            return
        }

        servers[index].alertConfiguration = alertConfiguration
        save()
    }

    func updateGlobalAlertSettings(barkURL: String, cooldownMinutes: Int) {
        let normalizedBarkURL = barkURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCooldown = max(1, cooldownMinutes)
        guard alertSettings.barkURL != normalizedBarkURL || alertSettings.cooldownMinutes != normalizedCooldown else {
            return
        }

        alertSettings = AlertSettings(
            barkURL: normalizedBarkURL,
            cooldownMinutes: normalizedCooldown
        )
        saveAlertSettings()
    }

    func refreshRemoteAlertStatus(for config: ServerConfig) async {
        guard let latestConfig = latestAlertConfig(for: config.id) else { return }
        beginRemoteAlertOperation(for: latestConfig.id)
        defer { endRemoteAlertOperation(for: latestConfig.id) }

        switch await SSHMonitorService.fetchRemoteAlertStatus(config: latestConfig) {
        case .success(var status):
            status.lastCheckedAt = Date()
            if status.isInstalled {
                status.lastUpdatedAt = remoteAlertStatusByServerID[latestConfig.id]?.lastUpdatedAt
            }
            remoteAlertStatusByServerID[latestConfig.id] = status
        case .failure(let error):
            mergeRemoteAlertFailure(error.message, for: latestConfig.id)
        }

        saveCachedInfo()
    }

    func deployRemoteAlert(for config: ServerConfig) async {
        guard let latestConfig = latestAlertConfig(for: config.id) else { return }
        beginRemoteAlertOperation(for: latestConfig.id)
        defer { endRemoteAlertOperation(for: latestConfig.id) }

        switch await SSHMonitorService.deployCPUAlert(config: latestConfig) {
        case .success(var status):
            let now = Date()
            status.lastCheckedAt = now
            status.lastUpdatedAt = now
            status.lastMessage = "已在目标服务器安装并启用远端告警"
            status.lastError = nil
            remoteAlertStatusByServerID[latestConfig.id] = status
        case .failure(let error):
            mergeRemoteAlertFailure(error.message, for: latestConfig.id)
        }

        save()
        saveCachedInfo()
    }

    func removeRemoteAlert(for config: ServerConfig) async {
        guard let latestConfig = latestAlertConfig(for: config.id) else { return }
        beginRemoteAlertOperation(for: latestConfig.id)
        defer { endRemoteAlertOperation(for: latestConfig.id) }

        switch await SSHMonitorService.removeCPUAlert(config: latestConfig) {
        case .success(var status):
            let now = Date()
            status.lastCheckedAt = now
            status.lastUpdatedAt = now
            status.lastMessage = "已从目标服务器卸载远端告警"
            status.lastError = nil
            remoteAlertStatusByServerID[latestConfig.id] = status
        case .failure(let error):
            mergeRemoteAlertFailure(error.message, for: latestConfig.id)
        }

        save()
        saveCachedInfo()
    }

    func sendRemoteAlertTest(for config: ServerConfig) async {
        guard let latestConfig = latestAlertConfig(for: config.id) else { return }
        beginRemoteAlertOperation(for: latestConfig.id)
        defer { endRemoteAlertOperation(for: latestConfig.id) }

        switch await SSHMonitorService.sendTestBarkNotification(config: latestConfig) {
        case .success(let message):
            var status = remoteAlertStatusByServerID[latestConfig.id] ?? RemoteAlertStatus()
            let now = Date()
            status.lastCheckedAt = now
            status.lastUpdatedAt = now
            status.lastMessage = message
            status.lastError = nil
            remoteAlertStatusByServerID[latestConfig.id] = status
        case .failure(let error):
            mergeRemoteAlertFailure(error.message, for: latestConfig.id)
        }

        saveCachedInfo()
    }

    func refreshAllIfNeeded(forceDynamic: Bool = false, forceStatic: Bool = false) async {
        let requests = servers.compactMap { makeRefreshRequest(for: $0, forceDynamic: forceDynamic, forceStatic: forceStatic) }
        await refresh(requests)
    }

    func refreshServer(_ config: ServerConfig, forceDynamic: Bool = false, forceStatic: Bool = false) async {
        guard let request = makeRefreshRequest(for: config, forceDynamic: forceDynamic, forceStatic: forceStatic) else {
            return
        }
        await refresh([request])
    }

    private func makeRefreshRequest(
        for config: ServerConfig,
        forceDynamic: Bool,
        forceStatic: Bool
    ) -> RefreshRequest? {
        if refreshingServerIDs.contains(config.id) {
            return nil
        }

        let shouldRefreshStatic = forceStatic || staticInfoByServerID[config.id] == nil || isStaticRefreshDue(config.id)
        let shouldRefreshDynamic = forceDynamic || dynamicInfoByServerID[config.id] == nil || isDynamicRefreshDue(config.id)

        if shouldRefreshStatic {
            return .full(config)
        }
        if shouldRefreshDynamic {
            return .dynamic(config)
        }

        return nil
    }

    private func refresh(_ requests: [RefreshRequest]) async {
        let deduped = requests.filter { request in
            switch request {
            case .full(let config), .dynamic(let config):
                return !refreshingServerIDs.contains(config.id)
            }
        }
        guard !deduped.isEmpty else { return }

        for request in deduped {
            switch request {
            case .full(let config), .dynamic(let config):
                refreshingServerIDs.insert(config.id)
            }
        }

        var pendingIDs = Set<UUID>()
        for request in deduped {
            switch request {
            case .full(let config), .dynamic(let config):
                pendingIDs.insert(config.id)
            }
        }

        let batchStartedAt = Date()

        await withTaskGroup(of: RefreshResult?.self) { group in
            for request in deduped {
                let startDelay = refreshStartDelay(for: request, totalRequestCount: deduped.count)
                switch request {
                case .full(let config):
                    group.addTask {
                        if Task.isCancelled { return nil }
                        if startDelay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
                        }
                        if Task.isCancelled { return nil }
                        let stats = await SSHMonitorService.fetchStats(config: config)
                        if Task.isCancelled { return nil }
                        return .full(config.id, stats)
                    }
                case .dynamic(let config):
                    group.addTask {
                        if Task.isCancelled { return nil }
                        if startDelay > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(startDelay * 1_000_000_000))
                        }
                        if Task.isCancelled { return nil }
                        let dynamic = await SSHMonitorService.fetchDynamicInfo(config: config)
                        if Task.isCancelled { return nil }
                        return .dynamic(config.id, dynamic)
                    }
                }
            }

            for await result in group {
                guard let result else { continue }
                let receivedAt = Date()
                switch result {
                case .full(let id, let stats):
                    let mergedStaticInfo = mergeStaticInfo(
                        current: staticInfoByServerID[id],
                        update: ServerStaticInfo(stats: stats)
                    )
                    if let mergedStaticInfo {
                        staticInfoByServerID[id] = mergedStaticInfo
                        lastStaticRefreshDates[id] = batchStartedAt
                    }
                    let resolvedDynamicInfo = resolvedDynamicInfoUpdate(
                        serverID: id,
                        incoming: ServerDynamicInfo(stats: stats),
                        now: receivedAt
                    )
                    dynamicInfoByServerID[id] = resolvedDynamicInfo
                    lastDynamicRefreshDates[id] = batchStartedAt
                    refreshingServerIDs.remove(id)
                case .dynamic(let id, let dynamic):
                    let resolvedDynamicInfo = resolvedDynamicInfoUpdate(
                        serverID: id,
                        incoming: dynamic,
                        now: receivedAt
                    )
                    dynamicInfoByServerID[id] = resolvedDynamicInfo
                    lastDynamicRefreshDates[id] = batchStartedAt
                    refreshingServerIDs.remove(id)
                }
                switch result {
                case .full(let id, _), .dynamic(let id, _):
                    pendingIDs.remove(id)
                }
                saveCachedInfo()
            }
        }

        // Requests canceled by view/task lifecycle should not keep "refreshing" stuck
        for id in pendingIDs {
            refreshingServerIDs.remove(id)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(data, forKey: serversKey)
        }
    }

    private func saveAlertSettings() {
        if let data = try? JSONEncoder().encode(alertSettings) {
            UserDefaults.standard.set(data, forKey: alertSettingsKey)
        }
    }

    private func saveCachedInfo() {
        if let data = try? JSONEncoder().encode(staticInfoByServerID) {
            UserDefaults.standard.set(data, forKey: staticInfoKey)
        }
        if let data = try? JSONEncoder().encode(dynamicInfoByServerID) {
            UserDefaults.standard.set(data, forKey: dynamicInfoKey)
        }
        if let data = try? JSONEncoder().encode(remoteAlertStatusByServerID) {
            UserDefaults.standard.set(data, forKey: remoteAlertStatusKey)
        }
    }

    private func saveCollapsedServerIDs() {
        if let data = try? JSONEncoder().encode(collapsedServerIDs) {
            UserDefaults.standard.set(data, forKey: collapsedServerIDsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            servers = decoded
        }
    }

    private func loadAlertSettings() {
        if let data = UserDefaults.standard.data(forKey: alertSettingsKey),
           let decoded = try? JSONDecoder().decode(AlertSettings.self, from: data) {
            alertSettings = decoded
            return
        }

        let migratedBarkURL = servers
            .lazy
            .map { $0.barkURL.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let migratedCooldown = servers
            .lazy
            .map { max(1, $0.alertConfiguration.cooldownMinutes) }
            .first ?? 10
        alertSettings = AlertSettings(
            barkURL: migratedBarkURL,
            cooldownMinutes: migratedCooldown
        )
        saveAlertSettings()
    }

    private func loadCachedInfo() {
        let validIDs = Set(servers.map(\.id))

        if let staticData = UserDefaults.standard.data(forKey: staticInfoKey),
           let decodedStatic = try? JSONDecoder().decode([UUID: ServerStaticInfo].self, from: staticData) {
            staticInfoByServerID = decodedStatic.filter { validIDs.contains($0.key) }
        }

        if let dynamicData = UserDefaults.standard.data(forKey: dynamicInfoKey),
           let decodedDynamic = try? JSONDecoder().decode([UUID: ServerDynamicInfo].self, from: dynamicData) {
            dynamicInfoByServerID = decodedDynamic.filter { validIDs.contains($0.key) }
        }

        if let alertStatusData = UserDefaults.standard.data(forKey: remoteAlertStatusKey),
           let decodedAlertStatus = try? JSONDecoder().decode([UUID: RemoteAlertStatus].self, from: alertStatusData) {
            remoteAlertStatusByServerID = decodedAlertStatus.filter { validIDs.contains($0.key) }
        }

        if let collapsedData = UserDefaults.standard.data(forKey: collapsedServerIDsKey),
           let decodedCollapsedIDs = try? JSONDecoder().decode(Set<UUID>.self, from: collapsedData) {
            collapsedServerIDs = Set(decodedCollapsedIDs.filter { validIDs.contains($0) })
        }

        migrateLegacyStatsIfNeeded(validIDs: validIDs)

        let now = Date()
        for id in staticInfoByServerID.keys {
            lastStaticRefreshDates[id] = now
        }
        for (id, dynamicInfo) in dynamicInfoByServerID {
            lastDynamicRefreshDates[id] = now.addingTimeInterval(-dynamicRefreshInterval)
            if dynamicInfo.isOnline {
                lastSuccessfulDynamicRefreshDates[id] = now
                consecutiveDynamicFailureCounts[id] = 0
            }
        }
    }

    private func migrateLegacyStatsIfNeeded(validIDs: Set<UUID>) {
        guard let legacyData = UserDefaults.standard.data(forKey: legacyStatsKey),
              let legacyStats = try? JSONDecoder().decode([UUID: ServerStats].self, from: legacyData) else {
            return
        }

        for (id, stats) in legacyStats where validIDs.contains(id) {
            if staticInfoByServerID[id] == nil {
                staticInfoByServerID[id] = ServerStaticInfo(stats: stats)
            }
            if dynamicInfoByServerID[id] == nil {
                dynamicInfoByServerID[id] = ServerDynamicInfo(stats: stats)
            }
        }

        saveCachedInfo()
    }

    private func isStaticRefreshDue(_ id: UUID) -> Bool {
        guard let lastRefresh = lastStaticRefreshDates[id] else {
            return true
        }
        return Date().timeIntervalSince(lastRefresh) >= staticRefreshInterval
    }

    private func isDynamicRefreshDue(_ id: UUID) -> Bool {
        guard let lastRefresh = lastDynamicRefreshDates[id] else {
            return true
        }
        return Date().timeIntervalSince(lastRefresh) >= dynamicRefreshInterval
    }

    private func mergeStaticInfo(current: ServerStaticInfo?, update: ServerStaticInfo) -> ServerStaticInfo? {
        guard hasMeaningfulStaticInfo(update) || current != nil else {
            return nil
        }

        var merged = current ?? ServerStaticInfo()
        if !update.osName.isEmpty {
            merged.osName = update.osName
        }
        if !update.hostname.isEmpty {
            merged.hostname = update.hostname
        }
        if !update.cpuModel.isEmpty {
            merged.cpuModel = update.cpuModel
        }
        if update.cpuCores > 0 {
            merged.cpuCores = update.cpuCores
        }
        if !update.cpuFrequency.isEmpty {
            merged.cpuFrequency = update.cpuFrequency
        }
        if update.memTotal > 0 {
            merged.memTotal = update.memTotal
        }
        return merged
    }

    private func resolvedDynamicInfoUpdate(
        serverID: UUID,
        incoming: ServerDynamicInfo,
        now: Date
    ) -> ServerDynamicInfo {
        if incoming.isOnline {
            consecutiveDynamicFailureCounts[serverID] = 0
            lastSuccessfulDynamicRefreshDates[serverID] = now
            var resolvedIncoming = incoming
            applyDerivedMetrics(
                to: &resolvedIncoming,
                previous: dynamicInfoByServerID[serverID],
                capturedAt: now
            )
            return resolvedIncoming
        }

        let nextFailureCount = (consecutiveDynamicFailureCounts[serverID] ?? 0) + 1
        consecutiveDynamicFailureCounts[serverID] = nextFailureCount
        handleRepeatedConnectionFailureIfNeeded(
            serverID: serverID,
            failureCount: nextFailureCount
        )

        guard shouldDelayOfflineTransition(
            serverID: serverID,
            failureCount: nextFailureCount,
            now: now
        ),
        let currentDynamicInfo = dynamicInfoByServerID[serverID] else {
            return incoming
        }

        var preservedDynamicInfo = currentDynamicInfo
        if !incoming.diagnostics.isEmpty {
            preservedDynamicInfo.diagnostics = incoming.diagnostics
        }
        if !incoming.rawOutput.isEmpty {
            preservedDynamicInfo.rawOutput = incoming.rawOutput
        }
        return preservedDynamicInfo
    }

    private func applyDerivedMetrics(
        to dynamicInfo: inout ServerDynamicInfo,
        previous: ServerDynamicInfo?,
        capturedAt: Date
    ) {
        guard var currentSample = dynamicInfo.liveSample, currentSample.hasCounters else {
            if let previous, previous.isOnline {
                dynamicInfo.liveSample = previous.liveSample
            }
            preserveDerivedMetrics(from: previous, to: &dynamicInfo)
            return
        }

        currentSample.capturedAt = capturedAt
        dynamicInfo.liveSample = currentSample

        guard let previous,
              previous.isOnline,
              let previousSample = previous.liveSample,
              let previousCapturedAt = previousSample.capturedAt else {
            resetDerivedMetrics(to: &dynamicInfo)
            return
        }

        let elapsed = capturedAt.timeIntervalSince(previousCapturedAt)
        guard elapsed > 0, elapsed <= maxDerivedMetricSampleAge else {
            // Instantaneous rates should not survive long gaps such as app relaunches.
            resetDerivedMetrics(to: &dynamicInfo)
            return
        }

        if let cpuUsage = deriveCPUUsage(previous: previousSample, current: currentSample) {
            dynamicInfo.cpuUsage = cpuUsage
        } else {
            dynamicInfo.cpuUsage = previous.cpuUsage
        }

        if let downloadBytesPerSecond = deriveBytesPerSecond(
            current: currentSample.networkRxBytes,
            previous: previousSample.networkRxBytes,
            elapsed: elapsed
        ) {
            dynamicInfo.downloadSpeed = formatRate(downloadBytesPerSecond)
        } else {
            dynamicInfo.downloadSpeed = previous.downloadSpeed
        }

        if let uploadBytesPerSecond = deriveBytesPerSecond(
            current: currentSample.networkTxBytes,
            previous: previousSample.networkTxBytes,
            elapsed: elapsed
        ) {
            dynamicInfo.uploadSpeed = formatRate(uploadBytesPerSecond)
        } else {
            dynamicInfo.uploadSpeed = previous.uploadSpeed
        }

        if let diskReadBytesPerSecond = deriveBytesPerSecond(
            current: currentSample.diskReadSectors,
            previous: previousSample.diskReadSectors,
            elapsed: elapsed,
            multiplier: 512
        ) {
            dynamicInfo.diskReadSpeed = formatRate(diskReadBytesPerSecond)
        } else {
            dynamicInfo.diskReadSpeed = previous.diskReadSpeed
        }

        if let diskWriteBytesPerSecond = deriveBytesPerSecond(
            current: currentSample.diskWriteSectors,
            previous: previousSample.diskWriteSectors,
            elapsed: elapsed,
            multiplier: 512
        ) {
            dynamicInfo.diskWriteSpeed = formatRate(diskWriteBytesPerSecond)
        } else {
            dynamicInfo.diskWriteSpeed = previous.diskWriteSpeed
        }
    }

    private func preserveDerivedMetrics(from previous: ServerDynamicInfo?, to dynamicInfo: inout ServerDynamicInfo) {
        guard let previous, previous.isOnline else { return }
        dynamicInfo.cpuUsage = previous.cpuUsage
        dynamicInfo.downloadSpeed = previous.downloadSpeed
        dynamicInfo.uploadSpeed = previous.uploadSpeed
        dynamicInfo.diskReadSpeed = previous.diskReadSpeed
        dynamicInfo.diskWriteSpeed = previous.diskWriteSpeed
    }

    private func resetDerivedMetrics(to dynamicInfo: inout ServerDynamicInfo) {
        dynamicInfo.cpuUsage = 0
        dynamicInfo.downloadSpeed = "0k/s"
        dynamicInfo.uploadSpeed = "0k/s"
        dynamicInfo.diskReadSpeed = "0k/s"
        dynamicInfo.diskWriteSpeed = "0k/s"
    }

    private func deriveCPUUsage(previous: ServerLiveSample, current: ServerLiveSample) -> Double? {
        guard let previousTotal = previous.cpuTotalTicks,
              let currentTotal = current.cpuTotalTicks,
              let previousIdle = previous.cpuIdleTicks,
              let currentIdle = current.cpuIdleTicks else {
            return nil
        }

        let totalDelta = currentTotal - previousTotal
        guard totalDelta > 0 else { return 0 }

        let idleDelta = max(0, currentIdle - previousIdle)
        let usage = (totalDelta - idleDelta) / totalDelta
        return min(max(usage, 0), 1)
    }

    private func deriveBytesPerSecond(
        current: Double?,
        previous: Double?,
        elapsed: TimeInterval,
        multiplier: Double = 1
    ) -> Double? {
        guard let current, let previous, elapsed > 0 else {
            return nil
        }

        let delta = max(0, current - previous) * multiplier
        return delta / elapsed
    }

    private func formatRate(_ bytesPerSecond: Double) -> String {
        let kilobytesPerSecond = max(0, bytesPerSecond) / 1024
        let roundedKilobytesPerSecond = (kilobytesPerSecond * 10).rounded() / 10

        if roundedKilobytesPerSecond <= 0 {
            return "0k/s"
        }

        if roundedKilobytesPerSecond < 1024 {
            return String(format: "%.1fk/s", roundedKilobytesPerSecond)
        }

        return String(format: "%.1fMB/s", roundedKilobytesPerSecond / 1024)
    }

    private func refreshStartDelay(
        for request: RefreshRequest,
        totalRequestCount: Int
    ) -> TimeInterval {
        guard totalRequestCount >= 4 else { return 0 }

        let slotCount = min(maxRefreshBatchStaggerSlots, totalRequestCount)
        guard slotCount > 1 else { return 0 }

        let serverID: UUID
        switch request {
        case .full(let config), .dynamic(let config):
            serverID = config.id
        }

        let slot = staggerSlot(for: serverID, slotCount: slotCount)
        return Double(slot) * refreshBatchStaggerInterval
    }

    private func staggerSlot(for serverID: UUID, slotCount: Int) -> Int {
        guard slotCount > 0 else { return 0 }

        var accumulator = 0
        for scalar in serverID.uuidString.unicodeScalars {
            accumulator = (accumulator * 33 + Int(scalar.value)) % slotCount
        }
        return accumulator
    }

    private func handleRepeatedConnectionFailureIfNeeded(
        serverID: UUID,
        failureCount: Int
    ) {
        guard failureCount == autoCollapseFailureThreshold,
              !collapsedServerIDs.contains(serverID),
              latestConfig(for: serverID) != nil else {
            return
        }

        setCollapsed(true, for: serverID)
    }

    private func shouldDelayOfflineTransition(
        serverID: UUID,
        failureCount: Int,
        now: Date
    ) -> Bool {
        guard failureCount < offlineTransitionFailureThreshold,
              let currentDynamicInfo = dynamicInfoByServerID[serverID],
              currentDynamicInfo.isOnline else {
            return false
        }

        let lastSuccess = lastSuccessfulDynamicRefreshDates[serverID] ?? lastDynamicRefreshDates[serverID]
        guard let lastSuccess else {
            return false
        }

        return now.timeIntervalSince(lastSuccess) <= offlineTransitionGraceInterval
    }

    private func hasMeaningfulStaticInfo(_ info: ServerStaticInfo) -> Bool {
        !info.osName.isEmpty ||
        !info.hostname.isEmpty ||
        !info.cpuModel.isEmpty ||
        info.cpuCores > 0 ||
        !info.cpuFrequency.isEmpty ||
        info.memTotal > 0
    }

    private func latestConfig(for id: UUID) -> ServerConfig? {
        servers.first(where: { $0.id == id })
    }

    private func latestAlertConfig(for id: UUID) -> ServerConfig? {
        guard var config = latestConfig(for: id) else {
            return nil
        }
        config.barkURL = alertSettings.barkURL
        config.alertConfiguration.cooldownMinutes = alertSettings.cooldownMinutes
        return config
    }

    private func beginRemoteAlertOperation(for id: UUID) {
        remoteAlertOperationServerIDs.insert(id)
    }

    private func endRemoteAlertOperation(for id: UUID) {
        remoteAlertOperationServerIDs.remove(id)
    }

    private func mergeRemoteAlertFailure(_ message: String, for id: UUID) {
        var status = remoteAlertStatusByServerID[id] ?? RemoteAlertStatus()
        status.lastCheckedAt = Date()
        status.lastError = message
        status.lastMessage = ""
        remoteAlertStatusByServerID[id] = status
    }
}
