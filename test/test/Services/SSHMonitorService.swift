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
    echo "=WIFI_PHY_BANDS="; (if command -v iw >/dev/null 2>&1 && [ -d /sys/class/ieee80211 ]; then found=""; for p in /sys/class/ieee80211/phy*; do [ -d "$p" ] || continue; phy=$(basename "$p"); band=$(iw phy "$phy" info 2>/dev/null | awk '/MHz/ {for (i=1; i<=NF; i++) {if ($i == "MHz") {f=$(i-1)+0; if (f > 0) {if (f < 3000) print "24g"; else if (f < 7000) print "5g"; else print "6g";} exit}}}'); [ -n "$band" ] || band="unknown"; printf "%s,%s;" "$phy" "$band"; found=1; done; if [ -n "$found" ]; then echo; else echo "none"; fi; else echo "none"; fi)
    echo "=TEMP_SENSORS="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/temp}; label=$(cat "$d/type" 2>/dev/null); [ -n "$label" ] || label=$(basename "$d"); label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/ieee80211/phy*/device/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/*}; phy=$(printf '%s' "$f" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; d=${f%/*}; resolved=$(readlink -f "$d" 2>/dev/null); v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; phy=$(printf '%s' "$resolved" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; if [ -n "$found" ]; then echo; else echo "unavailable"; fi)
    echo "=CPU_TEMP="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); [ -n "$v" ] || continue; type_file="${f%/temp}/type"; type=$(cat "$type_file" 2>/dev/null); case "$type" in *cpu*|*CPU*|*pkg*|*x86_pkg_temp*|*soc*|*SoC*|*cpu-thermal*) echo "$v"; found=1; break ;; esac; done; if [ -z "$found" ]; then for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; echo "$v"; found=1; break; done; fi; [ -n "$found" ] || echo "unknown")
    echo "=MEM="; (awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} /MemFree:/ {f=$2} END {avail=(a>0)?a:f; if (t>0) {u=t-avail; if (u<0) u=0; printf "%.0f %.0f %.0f\\n", t/1024, avail/1024, u/1024} else print "0 0 0"}' /proc/meminfo 2>/dev/null || echo "0 0 0")
    echo "=DISK="; (df -kP / 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "0 0 0 0% /"}')
    echo "=DISK_OVERLAY="; (df -kP /overlay 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "none"}')
    echo "=NSS_LOAD="; (if [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi 2>/dev/null; elif [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load 2>/dev/null; else echo "unavailable"; fi)
    echo "=NSS_FREQ="; (if [ -r /proc/sys/dev/nss/clock/current_freq ]; then awk '{v=$1+0; if (v > 1000000) printf "%.0f\\n", v/1000000; else if (v > 1000) printf "%.0f\\n", v/1000; else printf "%.0f\\n", v; found=1} END {if (!found) print "unknown"}' /proc/sys/dev/nss/clock/current_freq 2>/dev/null; else echo "unknown"; fi)
    echo "=CPU_USAGE="; ((top -bn1 2>/dev/null || top -n1 2>/dev/null) | awk '/Cpu\\(s\\)|CPU:/ {for (i=1; i<=NF; i++) {if ($i ~ /id,|idle/) {v=$(i-1); gsub(/[^0-9.]/, "", v); if (v != "") {printf "%.1f\\n", 100 - v; found=1; exit}}}} END {if (!found) print "0"}')
    echo "=NET="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
    sleep 1
    echo "=NET2="; (awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null || echo "0 0")
    exit 0
    """

    private static let dynamicStatsScript = """
    echo "=UPTIME="; (cat /proc/uptime 2>/dev/null | awk '{print $1}' || uptime 2>/dev/null || echo 0)
    echo "=WIFI_PHY_BANDS="; (if command -v iw >/dev/null 2>&1 && [ -d /sys/class/ieee80211 ]; then found=""; for p in /sys/class/ieee80211/phy*; do [ -d "$p" ] || continue; phy=$(basename "$p"); band=$(iw phy "$phy" info 2>/dev/null | awk '/MHz/ {for (i=1; i<=NF; i++) {if ($i == "MHz") {f=$(i-1)+0; if (f > 0) {if (f < 3000) print "24g"; else if (f < 7000) print "5g"; else print "6g";} exit}}}'); [ -n "$band" ] || band="unknown"; printf "%s,%s;" "$phy" "$band"; found=1; done; if [ -n "$found" ]; then echo; else echo "none"; fi; else echo "none"; fi)
    echo "=TEMP_SENSORS="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/temp}; label=$(cat "$d/type" 2>/dev/null); [ -n "$label" ] || label=$(basename "$d"); label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/ieee80211/phy*/device/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/*}; phy=$(printf '%s' "$f" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; d=${f%/*}; resolved=$(readlink -f "$d" 2>/dev/null); v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; phy=$(printf '%s' "$resolved" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; if [ -n "$found" ]; then echo; else echo "unavailable"; fi)
    echo "=CPU_TEMP="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); [ -n "$v" ] || continue; type_file="${f%/temp}/type"; type=$(cat "$type_file" 2>/dev/null); case "$type" in *cpu*|*CPU*|*pkg*|*x86_pkg_temp*|*soc*|*SoC*|*cpu-thermal*) echo "$v"; found=1; break ;; esac; done; if [ -z "$found" ]; then for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; echo "$v"; found=1; break; done; fi; [ -n "$found" ] || echo "unknown")
    echo "=MEM="; (awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} /MemFree:/ {f=$2} END {avail=(a>0)?a:f; if (t>0) {u=t-avail; if (u<0) u=0; printf "%.0f %.0f %.0f\\n", t/1024, avail/1024, u/1024} else print "0 0 0"}' /proc/meminfo 2>/dev/null || echo "0 0 0")
    echo "=DISK="; (df -kP / 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "0 0 0 0% /"}')
    echo "=DISK_OVERLAY="; (df -kP /overlay 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "none"}')
    echo "=NSS_LOAD="; (if [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi 2>/dev/null; elif [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load 2>/dev/null; else echo "unavailable"; fi)
    echo "=NSS_FREQ="; (if [ -r /proc/sys/dev/nss/clock/current_freq ]; then awk '{v=$1+0; if (v > 1000000) printf "%.0f\\n", v/1000000; else if (v > 1000) printf "%.0f\\n", v/1000; else printf "%.0f\\n", v; found=1} END {if (!found) print "unknown"}' /proc/sys/dev/nss/clock/current_freq 2>/dev/null; else echo "unknown"; fi)
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
        var wifiPhyBands: [String: String] = [:]
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
            } else if line == "=WIFI_PHY_BANDS=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                wifiPhyBands = parseWiFiPhyBands(from: lines[i + 1])
            } else if line == "=TEMP_SENSORS=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyTemperatureSensors(from: lines[i + 1], wifiPhyBands: wifiPhyBands, to: &stats)
            } else if line == "=CPU_TEMP=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                if stats.cpuTemperatureC == nil {
                    stats.cpuTemperatureC = parseCPUTemperature(from: lines[i + 1])
                }
            } else if line == "=MEM=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyMemoryValues(from: lines[i + 1], to: &stats)
            } else if line == "=DISK=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyDiskValues(from: lines[i + 1], to: &stats)
            } else if line == "=DISK_OVERLAY=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyOverlayDiskValues(from: lines[i + 1], to: &stats)
            } else if line == "=NSS_LOAD=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNSSLoad(from: lines[i + 1], to: &stats)
            } else if line == "=NSS_FREQ=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNSSFrequency(from: lines[i + 1], to: &stats)
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
            "=DISK_OVERLAY=",
            "=NSS_LOAD=",
            "=NSS_FREQ=",
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
        var wifiPhyBands: [String: String] = [:]
        var seenMarkers = Set<String>()

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line == "=UPTIME=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                dynamic.uptime = parseUptime(lines[i + 1])
            } else if line == "=WIFI_PHY_BANDS=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                wifiPhyBands = parseWiFiPhyBands(from: lines[i + 1])
            } else if line == "=TEMP_SENSORS=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyTemperatureSensors(from: lines[i + 1], wifiPhyBands: wifiPhyBands, to: &dynamic)
            } else if line == "=CPU_TEMP=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                if dynamic.cpuTemperatureC == nil {
                    dynamic.cpuTemperatureC = parseCPUTemperature(from: lines[i + 1])
                }
            } else if line == "=MEM=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyMemoryValues(from: lines[i + 1], to: &dynamic)
            } else if line == "=DISK=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyDiskValues(from: lines[i + 1], to: &dynamic)
            } else if line == "=DISK_OVERLAY=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyOverlayDiskValues(from: lines[i + 1], to: &dynamic)
            } else if line == "=NSS_LOAD=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNSSLoad(from: lines[i + 1], to: &dynamic)
            } else if line == "=NSS_FREQ=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNSSFrequency(from: lines[i + 1], to: &dynamic)
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
            "=DISK_OVERLAY=",
            "=NSS_LOAD=",
            "=NSS_FREQ=",
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

    private static func applyDiskValues(from line: String, to stats: inout ServerStats) {
        if let disk = parseDiskInfo(from: line) {
            stats.rootDisk = disk
            stats.diskUsage = disk.usage
        } else {
            stats.rootDisk = nil
            stats.diskUsage = parseDiskUsage(from: line)
        }
    }

    private static func applyDiskValues(from line: String, to dynamic: inout ServerDynamicInfo) {
        if let disk = parseDiskInfo(from: line) {
            dynamic.rootDisk = disk
            dynamic.diskUsage = disk.usage
        } else {
            dynamic.rootDisk = nil
            dynamic.diskUsage = parseDiskUsage(from: line)
        }
    }

    private static func applyOverlayDiskValues(from line: String, to stats: inout ServerStats) {
        stats.overlayDisk = parseOptionalDiskInfo(from: line)
    }

    private static func applyOverlayDiskValues(from line: String, to dynamic: inout ServerDynamicInfo) {
        dynamic.overlayDisk = parseOptionalDiskInfo(from: line)
    }

    private static func applyNSSLoad(from line: String, to stats: inout ServerStats) {
        stats.nssCores = parseNSSCores(from: line)
    }

    private static func applyNSSLoad(from line: String, to dynamic: inout ServerDynamicInfo) {
        dynamic.nssCores = parseNSSCores(from: line)
    }

    private static func applyNSSFrequency(from line: String, to stats: inout ServerStats) {
        stats.nssFrequencyMHz = parseNSSFrequency(from: line)
    }

    private static func applyNSSFrequency(from line: String, to dynamic: inout ServerDynamicInfo) {
        dynamic.nssFrequencyMHz = parseNSSFrequency(from: line)
    }

    private static func applyTemperatureSensors(
        from line: String,
        wifiPhyBands: [String: String],
        to stats: inout ServerStats
    ) {
        let sensors = parseTemperatureSensors(from: line)
        let classified = classifyTemperatureSensors(sensors, wifiPhyBands: wifiPhyBands)
        stats.cpuTemperatureC = classified.cpuTemperatureC ?? stats.cpuTemperatureC
        stats.wifi24TemperatureC = classified.wifi24TemperatureC
        stats.wifi5TemperatureC = classified.wifi5TemperatureC
        stats.additionalTemperatureSensors = classified.additionalSensors
    }

    private static func applyTemperatureSensors(
        from line: String,
        wifiPhyBands: [String: String],
        to dynamic: inout ServerDynamicInfo
    ) {
        let sensors = parseTemperatureSensors(from: line)
        let classified = classifyTemperatureSensors(sensors, wifiPhyBands: wifiPhyBands)
        dynamic.cpuTemperatureC = classified.cpuTemperatureC ?? dynamic.cpuTemperatureC
        dynamic.wifi24TemperatureC = classified.wifi24TemperatureC
        dynamic.wifi5TemperatureC = classified.wifi5TemperatureC
        dynamic.additionalTemperatureSensors = classified.additionalSensors
    }

    private static func parseOptionalDiskInfo(from line: String) -> ServerDiskInfo? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "none" else { return nil }
        return parseDiskInfo(from: trimmed)
    }

    private static func parseDiskInfo(from line: String) -> ServerDiskInfo? {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count >= 5 else { return nil }

        let pct = String(parts[3]).replacingOccurrences(of: "%", with: "")
        let mountPoint = parts[4...].joined(separator: " ")

        return ServerDiskInfo(
            mountPoint: mountPoint.isEmpty ? "/" : mountPoint,
            totalMB: Int(Double(parts[0]) ?? 0),
            usedMB: Int(Double(parts[1]) ?? 0),
            availableMB: Int(Double(parts[2]) ?? 0),
            usage: (Double(pct) ?? 0) / 100.0
        )
    }

    private static func parseNSSCores(from line: String) -> [ServerNSSCoreInfo] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unavailable" else { return [] }

        return trimmed
            .split(separator: ";")
            .compactMap { segment -> ServerNSSCoreInfo? in
                let parts = segment.split(separator: ",")
                guard parts.count >= 4 else { return nil }
                let coreID = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let name = coreID.lowercased().hasPrefix("core") ? coreID : "Core \(coreID)"
                return ServerNSSCoreInfo(
                    name: name,
                    minUsage: (Double(parts[1]) ?? 0) / 100.0,
                    avgUsage: (Double(parts[2]) ?? 0) / 100.0,
                    maxUsage: (Double(parts[3]) ?? 0) / 100.0
                )
            }
    }

    private static func parseNSSFrequency(from line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unknown" else { return nil }
        return Double(trimmed)
    }

    private static func parseTemperatureSensors(from line: String) -> [ServerTemperatureSensor] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unavailable" else { return [] }

        var seen = Set<String>()
        var sensors: [ServerTemperatureSensor] = []

        for entry in trimmed.split(separator: ";") {
            let parts = entry.split(separator: ",", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let rawLabel = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = parseCPUTemperature(from: String(parts[1])) else { continue }

            let sensor = ServerTemperatureSensor(
                label: rawLabel.isEmpty ? "sensor" : rawLabel,
                valueC: value
            )
            let dedupeKey = "\(normalizeSensorLabel(sensor.label))|\(Int((sensor.valueC * 10).rounded()))"
            guard !seen.contains(dedupeKey) else { continue }
            seen.insert(dedupeKey)
            sensors.append(sensor)
        }

        return sensors
    }

    private static func parseWiFiPhyBands(from line: String) -> [String: String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "none" else { return [:] }

        var bands: [String: String] = [:]
        for entry in trimmed.split(separator: ";") {
            let parts = entry.split(separator: ",", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let phy = normalizeSensorLabel(String(parts[0]))
            let band = normalizeSensorLabel(String(parts[1]))
            guard !phy.isEmpty, !band.isEmpty else { continue }
            bands[phy] = band
        }
        return bands
    }

    private static func classifyTemperatureSensors(
        _ sensors: [ServerTemperatureSensor],
        wifiPhyBands: [String: String]
    ) -> (
        cpuTemperatureC: Double?,
        wifi24TemperatureC: Double?,
        wifi5TemperatureC: Double?,
        additionalSensors: [ServerTemperatureSensor]
    ) {
        var cpuTemperatureC: Double?
        var wifi24TemperatureC: Double?
        var wifi5TemperatureC: Double?
        var additionalSensors: [ServerTemperatureSensor] = []

        for sensor in sensors {
            let label = normalizeSensorLabel(sensor.label)
            let inferredBand = inferWiFiBand(from: label, wifiPhyBands: wifiPhyBands)

            if wifi24TemperatureC == nil && (isWiFi24Label(label) || inferredBand == "24g") {
                wifi24TemperatureC = sensor.valueC
            } else if wifi5TemperatureC == nil && (isWiFi5Label(label) || inferredBand == "5g") {
                wifi5TemperatureC = sensor.valueC
            } else if cpuTemperatureC == nil && isCPUTemperatureLabel(label) {
                cpuTemperatureC = sensor.valueC
            } else {
                additionalSensors.append(sensor)
            }
        }

        if cpuTemperatureC == nil {
            if let fallbackCPU = sensors.first(where: {
                let label = normalizeSensorLabel($0.label)
                let inferredBand = inferWiFiBand(from: label, wifiPhyBands: wifiPhyBands)
                return !isWiFi24Label(label) && !isWiFi5Label(label) && inferredBand == nil
            }) {
                cpuTemperatureC = fallbackCPU.valueC
                additionalSensors.removeAll {
                    normalizeSensorLabel($0.label) == normalizeSensorLabel(fallbackCPU.label) &&
                    abs($0.valueC - fallbackCPU.valueC) < 0.05
                }
            } else {
                cpuTemperatureC = sensors.first?.valueC
            }
        }

        return (cpuTemperatureC, wifi24TemperatureC, wifi5TemperatureC, additionalSensors)
    }

    private static func normalizeSensorLabel(_ label: String) -> String {
        label
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    private static func inferWiFiBand(from label: String, wifiPhyBands: [String: String]) -> String? {
        for (phy, band) in wifiPhyBands {
            guard !phy.isEmpty else { continue }
            if label.contains(phy) {
                return band
            }

            if phy.hasPrefix("phy") {
                let suffix = String(phy.dropFirst(3))
                if label.contains("phya\(suffix)") || label.contains("phy\(suffix)") {
                    return band
                }
            }
        }
        return nil
    }

    private static func isCPUTemperatureLabel(_ label: String) -> Bool {
        label.contains("cpu") ||
        label.contains("pkg") ||
        label.contains("package") ||
        label.contains("soc") ||
        label.contains("apss") ||
        label.contains("cluster")
    }

    private static func isWiFi24Label(_ label: String) -> Bool {
        (label.contains("wifi") || label.contains("wlan") || label.contains("radio") || label.contains("phy")) &&
        (label.contains("2g") || label.contains("24g") || label.contains("24ghz") || label.contains("2ghz"))
    }

    private static func isWiFi5Label(_ label: String) -> Bool {
        (label.contains("wifi") || label.contains("wlan") || label.contains("radio") || label.contains("phy")) &&
        (label.contains("5g") || label.contains("58g") || label.contains("5ghz"))
    }

    private static func parseCPUTemperature(from line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unknown", let value = Double(trimmed) else {
            return nil
        }
        if value >= 1000 {
            return value / 1000.0
        }
        return value
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
