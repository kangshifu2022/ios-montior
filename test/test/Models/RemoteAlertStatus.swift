import Foundation

struct RemoteAlertStatus: Codable, Sendable {
    var isInstalled: Bool = false
    var scriptPath: String = "~/.ios-monitor/cpu_alert.sh"
    var scheduleDescription: String = "cron every minute"
    var remoteRuleDescriptions: [String] = []
    var lastCheckedAt: Date? = nil
    var lastUpdatedAt: Date? = nil
    var lastMessage: String = ""
    var lastError: String? = nil

    var summaryText: String {
        if let lastError, !lastError.isEmpty {
            return lastError
        }
        if !lastMessage.isEmpty {
            return lastMessage
        }
        return isInstalled ? "已启用远端告警" : "未在服务器上安装远端告警"
    }
}
