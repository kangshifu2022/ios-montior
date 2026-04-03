import Foundation

struct AlertConfiguration: Codable, Hashable, Sendable {
    var cooldownMinutes: Int = 10
    var cpuUsageEnabled: Bool = false
    var cpuUsageThreshold: Int = 90
    var memoryUsageEnabled: Bool = false
    var memoryUsageThreshold: Int = 90
    var psiCPUEnabled: Bool = false
    var psiCPUThreshold: Int = 5
    var psiMemoryEnabled: Bool = false
    var psiMemoryThreshold: Int = 5
    var psiIOEnabled: Bool = false
    var psiIOThreshold: Int = 5
    var websiteEnabled: Bool = false
    var websiteURL: String = ""

    init(
        cooldownMinutes: Int = 10,
        cpuUsageEnabled: Bool = false,
        cpuUsageThreshold: Int = 90,
        memoryUsageEnabled: Bool = false,
        memoryUsageThreshold: Int = 90,
        psiCPUEnabled: Bool = false,
        psiCPUThreshold: Int = 5,
        psiMemoryEnabled: Bool = false,
        psiMemoryThreshold: Int = 5,
        psiIOEnabled: Bool = false,
        psiIOThreshold: Int = 5,
        websiteEnabled: Bool = false,
        websiteURL: String = ""
    ) {
        self.cooldownMinutes = max(1, cooldownMinutes)
        self.cpuUsageEnabled = cpuUsageEnabled
        self.cpuUsageThreshold = Self.clampedPercentage(cpuUsageThreshold, fallback: 90)
        self.memoryUsageEnabled = memoryUsageEnabled
        self.memoryUsageThreshold = Self.clampedPercentage(memoryUsageThreshold, fallback: 90)
        self.psiCPUEnabled = psiCPUEnabled
        self.psiCPUThreshold = Self.clampedPercentage(psiCPUThreshold, fallback: 5)
        self.psiMemoryEnabled = psiMemoryEnabled
        self.psiMemoryThreshold = Self.clampedPercentage(psiMemoryThreshold, fallback: 5)
        self.psiIOEnabled = psiIOEnabled
        self.psiIOThreshold = Self.clampedPercentage(psiIOThreshold, fallback: 5)
        self.websiteEnabled = websiteEnabled
        self.websiteURL = Self.normalizedWebsiteURL(websiteURL)
    }

    var hasEnabledRules: Bool {
        cpuUsageEnabled ||
        memoryUsageEnabled ||
        psiCPUEnabled ||
        psiMemoryEnabled ||
        psiIOEnabled ||
        (websiteEnabled && !websiteURL.isEmpty)
    }

    var enabledRuleDescriptions: [String] {
        var descriptions: [String] = []

        if cpuUsageEnabled {
            descriptions.append("CPU >= \(cpuUsageThreshold)%")
        }
        if memoryUsageEnabled {
            descriptions.append("内存 >= \(memoryUsageThreshold)%")
        }
        if psiCPUEnabled {
            descriptions.append("CPU PSI(avg10) >= \(psiCPUThreshold)%")
        }
        if psiMemoryEnabled {
            descriptions.append("内存 PSI(avg10) >= \(psiMemoryThreshold)%")
        }
        if psiIOEnabled {
            descriptions.append("IO PSI(avg10) >= \(psiIOThreshold)%")
        }
        if websiteEnabled, !websiteURL.isEmpty {
            descriptions.append("网站不可达: \(websiteURL)")
        }

        return descriptions
    }

    static func legacy(
        cpuAlertEnabled: Bool,
        cpuAlertThreshold: Int,
        cpuAlertCooldownMinutes: Int
    ) -> AlertConfiguration {
        AlertConfiguration(
            cooldownMinutes: cpuAlertCooldownMinutes,
            cpuUsageEnabled: cpuAlertEnabled,
            cpuUsageThreshold: cpuAlertThreshold
        )
    }

    static func normalizedWebsiteURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed.contains("://") {
            return trimmed
        }

        return "https://\(trimmed)"
    }

    private static func clampedPercentage(_ value: Int, fallback: Int) -> Int {
        let baseline = value == 0 ? fallback : value
        return min(max(baseline, 1), 100)
    }
}
