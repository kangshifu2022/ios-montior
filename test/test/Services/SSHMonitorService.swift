import Foundation
import Citadel
import NIOCore

final class SSHMonitorService {
    private struct SSHCommandFailure: Error, Sendable {
        let statusMessage: String
        let diagnostics: [String]
        let rawOutput: String
    }

    static func fetchStats(config: ServerConfig) async -> ServerStats {
        switch await execute(
            config: config,
            script: fullStatsScript,
            connectionDiagnostics: [
                "failure stage: connect",
                "ssh stack: Citadel",
                "request kind: full",
                "algorithms: SSHAlgorithms.all"
            ],
            executeDiagnostics: [
                "failure stage: execute",
                "ssh stack: Citadel",
                "request kind: full",
                "algorithms: SSHAlgorithms.all"
            ]
        ) {
        case .success(let output):
            return parseStats(output: output, config: config)
        case .failure(let failure):
            var dynamicInfo = ServerDynamicInfo()
            dynamicInfo.isOnline = false
            dynamicInfo.statusMessage = failure.statusMessage
            dynamicInfo.diagnostics = failure.diagnostics
            dynamicInfo.rawOutput = failure.rawOutput
            return ServerStats(
                config: config,
                staticInfo: nil,
                dynamicInfo: dynamicInfo
            )
        }
    }

    static func fetchDynamicInfo(config: ServerConfig) async -> ServerDynamicInfo {
        switch await execute(
            config: config,
            script: dynamicStatsScript,
            connectionDiagnostics: [
                "failure stage: connect",
                "ssh stack: Citadel",
                "request kind: dynamic",
                "algorithms: SSHAlgorithms.all"
            ],
            executeDiagnostics: [
                "failure stage: execute",
                "ssh stack: Citadel",
                "request kind: dynamic",
                "algorithms: SSHAlgorithms.all"
            ]
        ) {
        case .success(let output):
            return parseDynamicInfo(output: output)
        case .failure(let failure):
            var dynamicInfo = ServerDynamicInfo()
            dynamicInfo.isOnline = false
            dynamicInfo.statusMessage = failure.statusMessage
            dynamicInfo.diagnostics = failure.diagnostics
            dynamicInfo.rawOutput = failure.rawOutput
            return dynamicInfo
        }
    }

    private static let fullStatsScript = """
    echo "=OS="; (if [ -f /etc/os-release ]; then . /etc/os-release; echo "${PRETTY_NAME:-$NAME}"; elif [ -f /etc/openwrt_release ]; then . /etc/openwrt_release; echo "${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"; else uname -sr; fi)
    echo "=HOSTNAME="; (hostname 2>/dev/null || uname -n 2>/dev/null || echo unknown)
    echo "=UPTIME="; (cat /proc/uptime 2>/dev/null | awk '{print $1}' || uptime 2>/dev/null || echo 0)
    echo "=CPU_INFO="; (awk -F: '/model name|Hardware|system type|machine/ {gsub(/^[ \\t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || uname -m 2>/dev/null || echo unknown)
    echo "=CPU_CORES="; (awk '/^processor/ {n++} END {print (n > 0 ? n : 1)}' /proc/cpuinfo 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    echo "=CPU_FREQ="; (if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then awk '{printf "%.0f MHz\\n", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null; elif [ -r /proc/cpuinfo ]; then awk -F: '/cpu MHz/ {gsub(/^[ \\t]+/, "", $2); printf "%.0f MHz\\n", $2; found=1; exit} /clock/ {gsub(/^[ \\t]+/, "", $2); print $2; found=1; exit} END {if (!found) print "unknown"}' /proc/cpuinfo 2>/dev/null; else echo "unknown"; fi)
    echo "=MEM="; (awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} /MemFree:/ {f=$2} END {avail=(a>0)?a:f; if (t>0) {u=t-avail; if (u<0) u=0; printf "%.0f %.0f %.0f\\n", t/1024, avail/1024, u/1024} else print "0 0 0"}' /proc/meminfo 2>/dev/null || echo "0 0 0")
    echo "=DISK="; (df -k / 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %s\\n", $2/1024, $3/1024, $5; found=1} END {if (!found) print "0 0 0%"}')
    echo "=CPU_USAGE="; ((top -bn1 2>/dev/null || top -n1 2>/dev/null) | awk '/Cpu\\(s\\)|CPU:/ {for (i=1; i<=NF; i++) {if ($i ~ /id,|idle/) {v=$(i-1); gsub(/[^0-9.]/, "", v); if (v != "") {printf "%.1f\\n", 100 - v; found=1; exit}}}} END {if (!found) print "0"}')
    echo "=NET="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
    sleep 1
    echo "=NET2="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
    exit 0
    """

    private static let dynamicStatsScript = """
    echo "=UPTIME="; (cat /proc/uptime 2>/dev/null | awk '{print $1}' || uptime 2>/dev/null || echo 0)
    echo "=MEM="; (awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} /MemFree:/ {f=$2} END {avail=(a>0)?a:f; if (t>0) {u=t-avail; if (u<0) u=0; printf "%.0f %.0f %.0f\\n", t/1024, avail/1024, u/1024} else print "0 0 0"}' /proc/meminfo 2>/dev/null || echo "0 0 0")
    echo "=DISK="; (df -k / 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %s\\n", $2/1024, $3/1024, $5; found=1} END {if (!found) print "0 0 0%"}')
    echo "=CPU_USAGE="; ((top -bn1 2>/dev/null || top -n1 2>/dev/null) | awk '/Cpu\\(s\\)|CPU:/ {for (i=1; i<=NF; i++) {if ($i ~ /id,|idle/) {v=$(i-1); gsub(/[^0-9.]/, "", v); if (v != "") {printf "%.1f\\n", 100 - v; found=1; exit}}}} END {if (!found) print "0"}')
    echo "=NET="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
    sleep 1
    echo "=NET2="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
    exit 0
    """

    private static func execute(
        config: ServerConfig,
        script: String,
        connectionDiagnostics: [String],
        executeDiagnostics: [String]
    ) async -> Result<String, SSHCommandFailure> {
        let algorithms = SSHAlgorithms.all

        do {
            let client = try await SSHClient.connect(
                host: config.host,
                port: config.port,
                authenticationMethod: .passwordBased(
                    username: config.username,
                    password: config.password
                ),
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                algorithms: algorithms,
                protocolOptions: [
                    .maximumPacketSize(1 << 20)
                ]
            )

            do {
                let output = try await client.executeCommand(
                    script,
                    maxResponseSize: 1 << 20,
                    mergeStreams: true
                )
                try? await client.close()
                return .success(String(buffer: output))
            } catch {
                try? await client.close()
                let message = String(describing: error)
                return .failure(
                    SSHCommandFailure(
                        statusMessage: describe(errorMessage: message),
                        diagnostics: executeDiagnostics,
                        rawOutput: message
                    )
                )
            }
        } catch {
            let message = String(describing: error)
            return .failure(
                SSHCommandFailure(
                    statusMessage: describe(errorMessage: message),
                    diagnostics: connectionDiagnostics,
                    rawOutput: message
                )
            )
        }
    }

    private static func parseStats(output: String, config: ServerConfig) -> ServerStats {
        var stats = ServerStats(config: config)
        stats.isOnline = true
        stats.statusMessage = "connected"
        stats.rawOutput = output

        let lines = output.components(separatedBy: "\n")
        var i = 0
        var net1: (rx: Double, tx: Double)?
        var seenMarkers = Set<String>()

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line == "=OS=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.osName = lines[i + 1].trimmingCharacters(in: .whitespaces)
            } else if line == "=HOSTNAME=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.hostname = lines[i + 1].trimmingCharacters(in: .whitespaces)
            } else if line == "=UPTIME=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.uptime = parseUptime(lines[i + 1])
            } else if line == "=CPU_INFO=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.cpuModel = lines[i + 1].trimmingCharacters(in: .whitespaces)
            } else if line == "=CPU_CORES=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.cpuCores = Int(lines[i + 1].trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line == "=CPU_FREQ=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.cpuFrequency = lines[i + 1].trimmingCharacters(in: .whitespaces)
            } else if line == "=MEM=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyMemoryValues(from: lines[i + 1], to: &stats)
            } else if line == "=DISK=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.diskUsage = parseDiskUsage(from: lines[i + 1])
            } else if line == "=CPU_USAGE=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.cpuUsage = parseCPUUsage(from: lines[i + 1])
            } else if line == "=NET=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                net1 = parseNetCounters(from: lines[i + 1])
            } else if line == "=NET2=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNetworkSpeeds(firstSample: net1, secondLine: lines[i + 1], to: &stats)
            }
            i += 1
        }

        let expectedMarkers = [
            "=OS=",
            "=HOSTNAME=",
            "=UPTIME=",
            "=CPU_INFO=",
            "=CPU_CORES=",
            "=CPU_FREQ=",
            "=MEM=",
            "=DISK=",
            "=CPU_USAGE=",
            "=NET=",
            "=NET2="
        ]
        let missingMarkers = expectedMarkers.filter { !seenMarkers.contains($0) }
        if !missingMarkers.isEmpty {
            stats.diagnostics.append("Missing script sections: \(missingMarkers.joined(separator: ", "))")
        }
        if stats.hostname.isEmpty {
            stats.diagnostics.append("hostname is empty")
        }
        if stats.osName.isEmpty {
            stats.diagnostics.append("os name is empty")
        }
        if stats.cpuModel.isEmpty {
            stats.diagnostics.append("cpu model is empty; likely unsupported /proc/cpuinfo format")
        }
        if stats.cpuCores <= 0 {
            stats.diagnostics.append("cpu core count could not be determined")
        }
        if stats.memTotal <= 0 {
            stats.diagnostics.append("memory total could not be determined")
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            stats.isOnline = false
            stats.statusMessage = "SSH command returned empty output"
            stats.diagnostics.append("Remote command completed but produced no stdout")
        } else if !missingMarkers.isEmpty || !stats.diagnostics.isEmpty {
            stats.statusMessage = "connected with partial data"
        }

        return stats
    }

    private static func parseDynamicInfo(output: String) -> ServerDynamicInfo {
        var dynamic = ServerDynamicInfo()
        dynamic.isOnline = true
        dynamic.statusMessage = "connected"
        dynamic.rawOutput = output

        let lines = output.components(separatedBy: "\n")
        var i = 0
        var net1: (rx: Double, tx: Double)?
        var seenMarkers = Set<String>()

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line == "=UPTIME=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                dynamic.uptime = parseUptime(lines[i + 1])
            } else if line == "=MEM=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyMemoryValues(from: lines[i + 1], to: &dynamic)
            } else if line == "=DISK=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                dynamic.diskUsage = parseDiskUsage(from: lines[i + 1])
            } else if line == "=CPU_USAGE=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                dynamic.cpuUsage = parseCPUUsage(from: lines[i + 1])
            } else if line == "=NET=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                net1 = parseNetCounters(from: lines[i + 1])
            } else if line == "=NET2=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNetworkSpeeds(firstSample: net1, secondLine: lines[i + 1], to: &dynamic)
            }
            i += 1
        }

        let expectedMarkers = [
            "=UPTIME=",
            "=MEM=",
            "=DISK=",
            "=CPU_USAGE=",
            "=NET=",
            "=NET2="
        ]
        let missingMarkers = expectedMarkers.filter { !seenMarkers.contains($0) }
        if !missingMarkers.isEmpty {
            dynamic.diagnostics.append("Missing script sections: \(missingMarkers.joined(separator: ", "))")
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            dynamic.isOnline = false
            dynamic.statusMessage = "SSH command returned empty output"
            dynamic.diagnostics.append("Remote command completed but produced no stdout")
        } else if !missingMarkers.isEmpty || !dynamic.diagnostics.isEmpty {
            dynamic.statusMessage = "connected with partial data"
        }

        return dynamic
    }

    private static func applyMemoryValues(from line: String, to stats: inout ServerStats) {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if parts.count >= 3 {
            let total = Double(parts[0]) ?? 0
            let available = Double(parts[1]) ?? 0
            let used = Double(parts[2]) ?? 0
            stats.memTotal = Int(total)
            stats.memAvailable = Int(available)
            stats.memUsage = total > 0 ? used / total : 0
        }
    }

    private static func applyMemoryValues(from line: String, to dynamic: inout ServerDynamicInfo) {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if parts.count >= 3 {
            let total = Double(parts[0]) ?? 0
            let available = Double(parts[1]) ?? 0
            let used = Double(parts[2]) ?? 0
            dynamic.memAvailable = Int(available)
            dynamic.memUsage = total > 0 ? used / total : 0
        }
    }

    private static func parseDiskUsage(from line: String) -> Double {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count >= 3 else { return 0 }
        let pct = String(parts[2]).replacingOccurrences(of: "%", with: "")
        return (Double(pct) ?? 0) / 100.0
    }

    private static func parseCPUUsage(from line: String) -> Double {
        (Double(line.trimmingCharacters(in: .whitespaces)) ?? 0) / 100.0
    }

    private static func parseNetCounters(from line: String) -> (rx: Double, tx: Double)? {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return (rx: Double(parts[0]) ?? 0, tx: Double(parts[1]) ?? 0)
    }

    private static func applyNetworkSpeeds(
        firstSample: (rx: Double, tx: Double)?,
        secondLine: String,
        to stats: inout ServerStats
    ) {
        guard let firstSample,
              let secondSample = parseNetCounters(from: secondLine) else {
            return
        }
        stats.downloadSpeed = formatSpeed(secondSample.rx - firstSample.rx)
        stats.uploadSpeed = formatSpeed(secondSample.tx - firstSample.tx)
    }

    private static func applyNetworkSpeeds(
        firstSample: (rx: Double, tx: Double)?,
        secondLine: String,
        to dynamic: inout ServerDynamicInfo
    ) {
        guard let firstSample,
              let secondSample = parseNetCounters(from: secondLine) else {
            return
        }
        dynamic.downloadSpeed = formatSpeed(secondSample.rx - firstSample.rx)
        dynamic.uploadSpeed = formatSpeed(secondSample.tx - firstSample.tx)
    }

    private static func parseUptime(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let seconds = Double(trimmed), seconds >= 0 {
            let total = Int(seconds)
            let days = total / 86_400
            let hours = (total % 86_400) / 3_600
            let minutes = (total % 3_600) / 60

            if days > 0 {
                return "up \(days)d \(hours)h"
            }
            if hours > 0 {
                return "up \(hours)h \(minutes)m"
            }
            return "up \(minutes)m"
        }

        if trimmed.contains("day") {
            let days = trimmed.components(separatedBy: "up").last?
                .components(separatedBy: "day").first?
                .trimmingCharacters(in: .whitespaces) ?? "0"
            return "up \(days)d"
        }
        return trimmed
    }

    private static func formatSpeed(_ bytes: Double) -> String {
        let kb = bytes / 1024
        if kb < 0 { return "0k/s" }
        if kb < 1024 {
            return String(format: "%.1fk/s", kb)
        } else {
            return String(format: "%.1fMB/s", kb / 1024)
        }
    }

    private static func describe(errorMessage: String) -> String {
        let message = errorMessage.isEmpty ? "SSH request failed" : errorMessage
        let lowercased = message.lowercased()

        if lowercased.contains("authentication") || lowercased.contains("auth") {
            return "authentication failed"
        }
        if lowercased.contains("keyexchangenegotiationfailure") || lowercased.contains("key exchange") {
            return "key exchange negotiation failed; server SSH algorithms are incompatible"
        }
        if lowercased.contains("timeout") {
            return "connection timed out"
        }
        if lowercased.contains("refused") {
            return "connection refused"
        }
        if lowercased.contains("no route") || lowercased.contains("unreachable") {
            return "host unreachable"
        }
        if lowercased.contains("host key") {
            return "host key validation failed"
        }
        return message
    }
}
