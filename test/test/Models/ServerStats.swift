import Foundation

struct ServerDiskInfo: Codable, Sendable {
    var mountPoint: String = "/"
    var totalMB: Int = 0
    var usedMB: Int = 0
    var availableMB: Int = 0
    var usage: Double = 0
}

struct ServerStaticInfo: Codable, Sendable {
    var osName: String = ""
    var hostname: String = ""
    var cpuModel: String = ""
    var cpuCores: Int = 0
    var cpuFrequency: String = ""
    var memTotal: Int = 0

    init() {}

    init(stats: ServerStats) {
        osName = stats.osName
        hostname = stats.hostname
        cpuModel = stats.cpuModel
        cpuCores = stats.cpuCores
        cpuFrequency = stats.cpuFrequency
        memTotal = stats.memTotal
    }
}

struct ServerDynamicInfo: Codable, Sendable {
    var isOnline: Bool = false
    var statusMessage: String = ""
    var diagnostics: [String] = []
    var rawOutput: String = ""
    var memAvailable: Int = 0
    var uptime: String = ""
    var cpuUsage: Double = 0
    var memUsage: Double = 0
    var diskUsage: Double = 0
    var rootDisk: ServerDiskInfo? = nil
    var downloadSpeed: String = "0k/s"
    var uploadSpeed: String = "0k/s"

    init() {}

    init(stats: ServerStats) {
        isOnline = stats.isOnline
        statusMessage = stats.statusMessage
        diagnostics = stats.diagnostics
        rawOutput = stats.rawOutput
        memAvailable = stats.memAvailable
        uptime = stats.uptime
        cpuUsage = stats.cpuUsage
        memUsage = stats.memUsage
        diskUsage = stats.diskUsage
        rootDisk = stats.rootDisk
        downloadSpeed = stats.downloadSpeed
        uploadSpeed = stats.uploadSpeed
    }
}

struct ServerStats: Codable, Sendable {
    var config: ServerConfig
    var isOnline: Bool = false
    var statusMessage: String = ""
    var diagnostics: [String] = []
    var rawOutput: String = ""
    var osName: String = ""
    var hostname: String = ""
    var cpuModel: String = ""
    var cpuCores: Int = 0
    var cpuFrequency: String = ""
    var memTotal: Int = 0
    var memAvailable: Int = 0
    var uptime: String = ""
    var cpuUsage: Double = 0
    var memUsage: Double = 0
    var diskUsage: Double = 0
    var rootDisk: ServerDiskInfo? = nil
    var downloadSpeed: String = "0k/s"
    var uploadSpeed: String = "0k/s"

    init(config: ServerConfig) {
        self.config = config
    }

    init(config: ServerConfig, staticInfo: ServerStaticInfo?, dynamicInfo: ServerDynamicInfo?) {
        self.config = config

        if let staticInfo {
            osName = staticInfo.osName
            hostname = staticInfo.hostname
            cpuModel = staticInfo.cpuModel
            cpuCores = staticInfo.cpuCores
            cpuFrequency = staticInfo.cpuFrequency
            memTotal = staticInfo.memTotal
        }

        if let dynamicInfo {
            isOnline = dynamicInfo.isOnline
            statusMessage = dynamicInfo.statusMessage
            diagnostics = dynamicInfo.diagnostics
            rawOutput = dynamicInfo.rawOutput
            memAvailable = dynamicInfo.memAvailable
            uptime = dynamicInfo.uptime
            cpuUsage = dynamicInfo.cpuUsage
            memUsage = dynamicInfo.memUsage
            diskUsage = dynamicInfo.diskUsage
            rootDisk = dynamicInfo.rootDisk
            downloadSpeed = dynamicInfo.downloadSpeed
            uploadSpeed = dynamicInfo.uploadSpeed
        }
    }
}
