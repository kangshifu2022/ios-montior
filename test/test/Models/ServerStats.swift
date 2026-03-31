import Foundation

struct ServerStats {
    var config: ServerConfig
    var isOnline: Bool = false
    var hostname: String = ""
    var cpuModel: String = ""
    var cpuCores: Int = 0
    var memTotal: Int = 0
    var uptime: String = ""
    var cpuUsage: Double = 0
    var memUsage: Double = 0
    var diskUsage: Double = 0
    var downloadSpeed: String = "0k/s"
    var uploadSpeed: String = "0k/s"
}
