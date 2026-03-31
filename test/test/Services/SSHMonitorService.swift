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
            echo "=HOSTNAME="; hostname
            echo "=UPTIME="; uptime
            echo "=CPU_INFO="; cat /proc/cpuinfo | grep 'model name' | head -1 | cut -d: -f2 | xargs
            echo "=CPU_CORES="; nproc
            echo "=MEM="; free -m | awk 'NR==2{print $2,$3}'
            echo "=DISK="; df -h / | awk 'NR==2{print $2,$3,$5}'
            echo "=CPU_USAGE="; top -bn1 | grep 'Cpu(s)' | awk '{print $2}' | cut -d'%' -f1
            echo "=NET="; cat /proc/net/dev | grep -v lo | grep ':' | head -1 | awk '{print $2,$10}'
            sleep 1
            echo "=NET2="; cat /proc/net/dev | grep -v lo | grep ':' | head -1 | awk '{print $2,$10}'
            """
            
            let output = try await client.executeCommand(script)
            let text = String(buffer: output)
            try await client.close()
            
            return parseStats(output: text, config: config)
            
        } catch {
            print("SSH error: \(error)")
            return ServerStats(config: config, isOnline: false)
        }
    }
    
    private static func parseStats(output: String, config: ServerConfig) -> ServerStats {
        var stats = ServerStats(config: config)
        stats.isOnline = true
        
        let lines = output.components(separatedBy: "\n")
        var i = 0
        var net1: (rx: Double, tx: Double)?
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            
            if line == "=HOSTNAME=" && i + 1 < lines.count {
                stats.hostname = lines[i + 1].trimmingCharacters(in: .whitespaces)
            } else if line == "=UPTIME=" && i + 1 < lines.count {
                stats.uptime = parseUptime(lines[i + 1])
            } else if line == "=CPU_INFO=" && i + 1 < lines.count {
                stats.cpuModel = lines[i + 1].trimmingCharacters(in: .whitespaces)
            } else if line == "=CPU_CORES=" && i + 1 < lines.count {
                stats.cpuCores = Int(lines[i + 1].trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line == "=MEM=" && i + 1 < lines.count {
                let parts = lines[i + 1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 2 {
                    let total = Double(parts[0]) ?? 0
                    let used = Double(parts[1]) ?? 0
                    stats.memTotal = Int(total)
                    stats.memUsage = total > 0 ? used / total : 0
                }
            } else if line == "=DISK=" && i + 1 < lines.count {
                let parts = lines[i + 1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 3 {
                    let pct = String(parts[2]).replacingOccurrences(of: "%", with: "")
                    stats.diskUsage = (Double(pct) ?? 0) / 100.0
                }
            } else if line == "=CPU_USAGE=" && i + 1 < lines.count {
                let val = lines[i + 1].trimmingCharacters(in: .whitespaces)
                stats.cpuUsage = (Double(val) ?? 0) / 100.0
            } else if line == "=NET=" && i + 1 < lines.count {
                let parts = lines[i + 1].trimmingCharacters(in: .whitespaces).split(separator: " ")
                if parts.count >= 2 {
                    net1 = (rx: Double(parts[0]) ?? 0, tx: Double(parts[1]) ?? 0)
                }
            } else if line == "=NET2=" && i + 1 < lines.count {
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
        
        return stats
    }
    
    private static func parseUptime(_ raw: String) -> String {
        if raw.contains("day") {
            let days = raw.components(separatedBy: "up").last?
                .components(separatedBy: "day").first?
                .trimmingCharacters(in: .whitespaces) ?? "0"
            return "up \(days)d"
        }
        return raw.trimmingCharacters(in: .whitespaces)
    }
    
    private static func formatSpeed(_ bytes: Double) -> String {
        let kb = bytes / 1024
        if kb < 0 { return "0k/s" }
        if kb < 1024 {
            return String(format: "%.1fk/s", kb)
        } else {
            return String(format: "%.1fm/s", kb / 1024)
        }
    }
}
