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

    private let serversKey = "saved_servers"
    private let staticInfoKey = "cached_server_static_info"
    private let dynamicInfoKey = "cached_server_dynamic_info"
    private let legacyStatsKey = "cached_server_stats"
    private var lastStaticRefreshDates: [UUID: Date] = [:]
    private var lastDynamicRefreshDates: [UUID: Date] = [:]
    private let staticRefreshInterval: TimeInterval = 60
    private let dynamicRefreshInterval: TimeInterval = 3

    init() {
        load()
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
            lastStaticRefreshDates.removeValue(forKey: server.id)
            lastDynamicRefreshDates.removeValue(forKey: server.id)
            refreshingServerIDs.remove(server.id)
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
            lastStaticRefreshDates.removeValue(forKey: $0)
            lastDynamicRefreshDates.removeValue(forKey: $0)
            refreshingServerIDs.remove($0)
        }
        save()
        saveCachedInfo()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        servers.move(fromOffsets: fromOffsets, toOffset: toOffset)
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

        await withTaskGroup(of: RefreshResult?.self) { group in
            for request in deduped {
                switch request {
                case .full(let config):
                    group.addTask {
                        if Task.isCancelled { return nil }
                        let stats = await SSHMonitorService.fetchStats(config: config)
                        if Task.isCancelled { return nil }
                        return .full(config.id, stats)
                    }
                case .dynamic(let config):
                    group.addTask {
                        if Task.isCancelled { return nil }
                        let dynamic = await SSHMonitorService.fetchDynamicInfo(config: config)
                        if Task.isCancelled { return nil }
                        return .dynamic(config.id, dynamic)
                    }
                }
            }

            for await result in group {
                guard let result else { continue }
                switch result {
                case .full(let id, let stats):
                    let mergedStaticInfo = mergeStaticInfo(
                        current: staticInfoByServerID[id],
                        update: ServerStaticInfo(stats: stats)
                    )
                    if let mergedStaticInfo {
                        staticInfoByServerID[id] = mergedStaticInfo
                        lastStaticRefreshDates[id] = Date()
                    }
                    dynamicInfoByServerID[id] = ServerDynamicInfo(stats: stats)
                    lastDynamicRefreshDates[id] = Date()
                    refreshingServerIDs.remove(id)
                case .dynamic(let id, let dynamic):
                    dynamicInfoByServerID[id] = dynamic
                    lastDynamicRefreshDates[id] = Date()
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

    private func saveCachedInfo() {
        if let data = try? JSONEncoder().encode(staticInfoByServerID) {
            UserDefaults.standard.set(data, forKey: staticInfoKey)
        }
        if let data = try? JSONEncoder().encode(dynamicInfoByServerID) {
            UserDefaults.standard.set(data, forKey: dynamicInfoKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: serversKey),
           let decoded = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            servers = decoded
        }
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

        migrateLegacyStatsIfNeeded(validIDs: validIDs)

        let now = Date()
        for id in staticInfoByServerID.keys {
            lastStaticRefreshDates[id] = now
        }
        for id in dynamicInfoByServerID.keys {
            lastDynamicRefreshDates[id] = now.addingTimeInterval(-dynamicRefreshInterval)
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

    private func hasMeaningfulStaticInfo(_ info: ServerStaticInfo) -> Bool {
        !info.osName.isEmpty ||
        !info.hostname.isEmpty ||
        !info.cpuModel.isEmpty ||
        info.cpuCores > 0 ||
        !info.cpuFrequency.isEmpty ||
        info.memTotal > 0
    }
}
