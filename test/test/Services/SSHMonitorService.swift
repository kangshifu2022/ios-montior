import Foundation
import Citadel
import NIOCore

class SSHMonitorService {
    
    static func fetchStats(config: ServerConfig) async -> ServerStats {
        do {
            let client = try await SSHClient.connect(
                host: config.host,
                port: config.port,
                authenticationMethod: .passwordBased(
                    username: config.username,
                    password: config.password
                ),
                hostKeyValidator: .acceptAnything(),
                reconnect: .never
            )
            
            let script = """
            echo "=HOSTNAME="; (hostname 2>/dev/null || uname -n 2>/dev/null || echo unknown)
            echo "=UPTIME="; (cat /proc/uptime 2>/dev/null | awk '{print $1}' || uptime 2>/dev/null || echo 0)
            echo "=CPU_INFO="; (awk -F: '/model name|Hardware|system type|machine/ {gsub(/^[ \\t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || uname -m 2>/dev/null || echo unknown)
            echo "=CPU_CORES="; (awk '/^processor/ {n++} END {print (n > 0 ? n : 1)}' /proc/cpuinfo 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
            echo "=MEM="; (awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} /MemFree:/ {f=$2} END {if (t>0) {u=t-((a>0)?a:f); if (u<0) u=0; printf "%.0f %.0f\\n", t/1024, u/1024} else print "0 0"}' /proc/meminfo 2>/dev/null || echo "0 0")
            echo "=DISK="; (df -k / 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %s\\n", $2/1024, $3/1024, $5; found=1} END {if (!found) print "0 0 0%"}')
            echo "=CPU_USAGE="; ((top -bn1 2>/dev/null || top -n1 2>/dev/null) | awk '/Cpu\\(s\\)|CPU:/ {for (i=1; i<=NF; i++) {if ($i ~ /id,|idle/) {v=$(i-1); gsub(/[^0-9.]/, "", v); if (v != "") {printf "%.1f\\n", 100 - v; found=1; exit}}}} END {if (!found) print "0"}')
            echo "=NET="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
            sleep 1
            echo "=NET2="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
            exit 0
            """
            
            let output = try await client.executeCommand(script)
            let text = String(buffer: output)
            try await client.close()
            
            return parseStats(output: text, config: config)
            
        } catch {
            print("SSH error: \(error)")
            return ServerStats(
                config: config,
                isOnline: false,
                statusMessage: describe(error: error),
                diagnostics: ["SSH connection or command execution failed"],
                rawOutput: String(describing: error)
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
            
            if line == "=HOSTNAME=" && i + 1 < lines.count {
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
            } else if line == "=MEM=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                let parts = lines[i + 1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 2 {
                    let total = Double(parts[0]) ?? 0
                    let used = Double(parts[1]) ?? 0
                    stats.memTotal = Int(total)
                    stats.memUsage = total > 0 ? used / total : 0
                }
            } else if line == "=DISK=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                let parts = lines[i + 1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 3 {
                    let pct = String(parts[2]).replacingOccurrences(of: "%", with: "")
                    stats.diskUsage = (Double(pct) ?? 0) / 100.0
                }
            } else if line == "=CPU_USAGE=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                let val = lines[i + 1].trimmingCharacters(in: .whitespaces)
                stats.cpuUsage = (Double(val) ?? 0) / 100.0
            } else if line == "=NET=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                let parts = lines[i + 1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 2 {
                    net1 = (rx: Double(parts[0]) ?? 0, tx: Double(parts[1]) ?? 0)
                }
            } else if line == "=NET2=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                let parts = lines[i + 1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 2, let n1 = net1 {
                    let rx2 = Double(parts[0]) ?? 0
                    let tx2 = Double(parts[1]) ?? 0
                    stats.downloadSpeed = formatSpeed(rx2 - n1.rx)
                    stats.uploadSpeed = formatSpeed(tx2 - n1.tx)
                }
            }
            i += 1
        }
        
        let expectedMarkers = [
            "=HOSTNAME=",
            "=UPTIME=",
            "=CPU_INFO=",
            "=CPU_CORES=",
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
    
    private static func describe(error: Error) -> String {
        let message = String(describing: error)
        let lowercased = message.lowercased()
        
        if lowercased.contains("authentication") || lowercased.contains("auth") {
            return "authentication failed"
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
