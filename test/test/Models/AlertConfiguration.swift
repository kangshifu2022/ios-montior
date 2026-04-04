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
    var websiteTargets: [String] = []

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
        websiteTargets: [String] = []
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
        self.websiteTargets = Self.normalizedWebsiteTargets(websiteTargets)
    }

    var hasEnabledRules: Bool {
        cpuUsageEnabled ||
        memoryUsageEnabled ||
        psiCPUEnabled ||
        psiMemoryEnabled ||
        psiIOEnabled ||
        (websiteEnabled && !websiteTargets.isEmpty)
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
        if websiteEnabled {
            for target in websiteTargets {
                descriptions.append("网站不可达: \(target)")
            }
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

    private enum CodingKeys: String, CodingKey {
        case cooldownMinutes
        case cpuUsageEnabled
        case cpuUsageThreshold
        case memoryUsageEnabled
        case memoryUsageThreshold
        case psiCPUEnabled
        case psiCPUThreshold
        case psiMemoryEnabled
        case psiMemoryThreshold
        case psiIOEnabled
        case psiIOThreshold
        case websiteEnabled
        case websiteTargets
        case websiteURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTargets = try container.decodeIfPresent([String].self, forKey: .websiteTargets) ?? []
        let legacyTarget = try container.decodeIfPresent(String.self, forKey: .websiteURL) ?? ""

        cooldownMinutes = max(1, try container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 10)
        cpuUsageEnabled = try container.decodeIfPresent(Bool.self, forKey: .cpuUsageEnabled) ?? false
        cpuUsageThreshold = Self.clampedPercentage(
            try container.decodeIfPresent(Int.self, forKey: .cpuUsageThreshold) ?? 90,
            fallback: 90
        )
        memoryUsageEnabled = try container.decodeIfPresent(Bool.self, forKey: .memoryUsageEnabled) ?? false
        memoryUsageThreshold = Self.clampedPercentage(
            try container.decodeIfPresent(Int.self, forKey: .memoryUsageThreshold) ?? 90,
            fallback: 90
        )
        psiCPUEnabled = try container.decodeIfPresent(Bool.self, forKey: .psiCPUEnabled) ?? false
        psiCPUThreshold = Self.clampedPercentage(
            try container.decodeIfPresent(Int.self, forKey: .psiCPUThreshold) ?? 5,
            fallback: 5
        )
        psiMemoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .psiMemoryEnabled) ?? false
        psiMemoryThreshold = Self.clampedPercentage(
            try container.decodeIfPresent(Int.self, forKey: .psiMemoryThreshold) ?? 5,
            fallback: 5
        )
        psiIOEnabled = try container.decodeIfPresent(Bool.self, forKey: .psiIOEnabled) ?? false
        psiIOThreshold = Self.clampedPercentage(
            try container.decodeIfPresent(Int.self, forKey: .psiIOThreshold) ?? 5,
            fallback: 5
        )
        websiteEnabled = try container.decodeIfPresent(Bool.self, forKey: .websiteEnabled) ?? false
        websiteTargets = Self.normalizedWebsiteTargets(decodedTargets + [legacyTarget])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cooldownMinutes, forKey: .cooldownMinutes)
        try container.encode(cpuUsageEnabled, forKey: .cpuUsageEnabled)
        try container.encode(cpuUsageThreshold, forKey: .cpuUsageThreshold)
        try container.encode(memoryUsageEnabled, forKey: .memoryUsageEnabled)
        try container.encode(memoryUsageThreshold, forKey: .memoryUsageThreshold)
        try container.encode(psiCPUEnabled, forKey: .psiCPUEnabled)
        try container.encode(psiCPUThreshold, forKey: .psiCPUThreshold)
        try container.encode(psiMemoryEnabled, forKey: .psiMemoryEnabled)
        try container.encode(psiMemoryThreshold, forKey: .psiMemoryThreshold)
        try container.encode(psiIOEnabled, forKey: .psiIOEnabled)
        try container.encode(psiIOThreshold, forKey: .psiIOThreshold)
        try container.encode(websiteEnabled, forKey: .websiteEnabled)
        try container.encode(Self.normalizedWebsiteTargets(websiteTargets), forKey: .websiteTargets)
    }

    static func normalizedWebsiteTarget(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if trimmed.contains("://") {
            return trimmed
        }

        if looksLikeHostWithPort(trimmed) {
            return trimmed
        }

        return "https://\(trimmed)"
    }

    static func normalizedWebsiteTargets(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { Self.normalizedWebsiteTarget($0) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    private static func clampedPercentage(_ value: Int, fallback: Int) -> Int {
        let baseline = value == 0 ? fallback : value
        return min(max(baseline, 1), 100)
    }

    private static func looksLikeHostWithPort(_ value: String) -> Bool {
        if value.hasPrefix("["),
           let closingBracket = value.firstIndex(of: "]"),
           value.index(after: closingBracket) < value.endIndex,
           value[value.index(after: closingBracket)] == ":" {
            let portStart = value.index(closingBracket, offsetBy: 2)
            guard portStart < value.endIndex else { return false }
            return value[portStart...].allSatisfy(\.isNumber)
        }

        guard let colon = value.lastIndex(of: ":") else {
            return false
        }

        let port = value[value.index(after: colon)...]
        let host = value[..<colon]
        return !host.isEmpty && !port.isEmpty && port.allSatisfy(\.isNumber)
    }
}
