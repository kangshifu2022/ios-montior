import Foundation

enum ConnectedDeviceConnectionType: String, Codable, Sendable {
    case wired = "wired"
    case wifi24 = "wifi24"
    case wifi5 = "wifi5"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .wired: return "有线"
        case .wifi24: return "WiFi 2.4G"
        case .wifi5: return "WiFi 5G"
        case .unknown: return "未知"
        }
    }
}

struct ConnectedDevice: Codable, Sendable, Identifiable {
    var id: String { mac }
    var ip: String = ""
    var mac: String = ""
    var hostname: String = ""
    var connectionType: ConnectedDeviceConnectionType = .unknown
    var signalDBm: Int? = nil

    var displayName: String {
        if !hostname.isEmpty && hostname != "*" && hostname != "?" {
            return hostname
        }
        return ip.isEmpty ? mac : ip
    }
}

struct RouterInfo: Codable, Sendable {
    var isRouter: Bool = false
    var connectedDevices: [ConnectedDevice] = []
}

struct ServerDiskInfo: Codable, Sendable {
    var mountPoint: String = "/"
    var totalMB: Int = 0
    var usedMB: Int = 0
    var availableMB: Int = 0
    var usage: Double = 0
}

struct ServerNSSCoreInfo: Codable, Sendable {
    var name: String = ""
    var minUsage: Double = 0
    var avgUsage: Double = 0
    var maxUsage: Double = 0
}

struct ServerTemperatureSensor: Codable, Sendable {
    var label: String = ""
    var valueC: Double = 0
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
    var cpuTemperatureC: Double? = nil
    var wifi24TemperatureC: Double? = nil
    var wifi5TemperatureC: Double? = nil
    var additionalTemperatureSensors: [ServerTemperatureSensor] = []
    var memUsage: Double = 0
    var diskUsage: Double = 0
    var rootDisk: ServerDiskInfo? = nil
    var overlayDisk: ServerDiskInfo? = nil
    var nssCores: [ServerNSSCoreInfo] = []
    var nssFrequencyMHz: Double? = nil
    var downloadSpeed: String = "0k/s"
    var uploadSpeed: String = "0k/s"
    var routerInfo: RouterInfo = RouterInfo()

    init() {}

    init(stats: ServerStats) {
        isOnline = stats.isOnline
        statusMessage = stats.statusMessage
        diagnostics = stats.diagnostics
        rawOutput = stats.rawOutput
        memAvailable = stats.memAvailable
        uptime = stats.uptime
        cpuUsage = stats.cpuUsage
        cpuTemperatureC = stats.cpuTemperatureC
        wifi24TemperatureC = stats.wifi24TemperatureC
        wifi5TemperatureC = stats.wifi5TemperatureC
        additionalTemperatureSensors = stats.additionalTemperatureSensors
        memUsage = stats.memUsage
        diskUsage = stats.diskUsage
        rootDisk = stats.rootDisk
        overlayDisk = stats.overlayDisk
        nssCores = stats.nssCores
        nssFrequencyMHz = stats.nssFrequencyMHz
        downloadSpeed = stats.downloadSpeed
        uploadSpeed = stats.uploadSpeed
        routerInfo = stats.routerInfo
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
    var cpuTemperatureC: Double? = nil
    var wifi24TemperatureC: Double? = nil
    var wifi5TemperatureC: Double? = nil
    var additionalTemperatureSensors: [ServerTemperatureSensor] = []
    var memUsage: Double = 0
    var diskUsage: Double = 0
    var rootDisk: ServerDiskInfo? = nil
    var overlayDisk: ServerDiskInfo? = nil
    var nssCores: [ServerNSSCoreInfo] = []
    var nssFrequencyMHz: Double? = nil
    var downloadSpeed: String = "0k/s"
    var uploadSpeed: String = "0k/s"
    var routerInfo: RouterInfo = RouterInfo()

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
            cpuTemperatureC = dynamicInfo.cpuTemperatureC
            wifi24TemperatureC = dynamicInfo.wifi24TemperatureC
            wifi5TemperatureC = dynamicInfo.wifi5TemperatureC
            additionalTemperatureSensors = dynamicInfo.additionalTemperatureSensors
            memUsage = dynamicInfo.memUsage
            diskUsage = dynamicInfo.diskUsage
            rootDisk = dynamicInfo.rootDisk
            overlayDisk = dynamicInfo.overlayDisk
            nssCores = dynamicInfo.nssCores
            nssFrequencyMHz = dynamicInfo.nssFrequencyMHz
            downloadSpeed = dynamicInfo.downloadSpeed
            uploadSpeed = dynamicInfo.uploadSpeed
            routerInfo = dynamicInfo.routerInfo
        }
    }
}
