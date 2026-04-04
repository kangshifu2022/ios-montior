import Foundation
import Citadel
import NIOCore

final class SSHMonitorService {
    private struct SSHCommandFailure: Error, Sendable {
        let statusMessage: String
        let diagnostics: [String]
        let rawOutput: String
    }

    struct RemoteAlertOperationError: Error, Sendable {
        let message: String
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

    static func fetchRemoteAlertStatus(config: ServerConfig) async -> Result<RemoteAlertStatus, RemoteAlertOperationError> {
        switch await execute(
            config: config,
            script: remoteAlertStatusScript,
            connectionDiagnostics: [
                "failure stage: connect",
                "ssh stack: Citadel",
                "request kind: remote-alert-status",
                "algorithms: SSHAlgorithms.all"
            ],
            executeDiagnostics: [
                "failure stage: execute",
                "ssh stack: Citadel",
                "request kind: remote-alert-status",
                "algorithms: SSHAlgorithms.all"
            ]
        ) {
        case .success(let output):
            return .success(parseRemoteAlertStatus(output: output))
        case .failure(let failure):
            return .failure(RemoteAlertOperationError(message: failure.statusMessage))
        }
    }

    static func deployCPUAlert(config: ServerConfig) async -> Result<RemoteAlertStatus, RemoteAlertOperationError> {
        guard let barkBaseURL = BarkService.pushBaseURLString(from: config.barkURL) else {
            return .failure(RemoteAlertOperationError(message: "Bark 测试地址无效，请粘贴 Bark App 里的测试地址"))
        }
        guard config.alertConfiguration.hasEnabledRules else {
            return .failure(RemoteAlertOperationError(message: "请至少启用一项告警规则"))
        }

        let deployCommands = makeRemoteAlertDeploymentCommands(config: config, barkBaseURL: barkBaseURL)
        for (index, command) in deployCommands.enumerated() {
            let requestKind = "remote-alert-deploy-step-\(index + 1)"
            switch await execute(
                config: config,
                script: command,
                connectionDiagnostics: [
                    "failure stage: connect",
                    "ssh stack: Citadel",
                    "request kind: \(requestKind)",
                    "algorithms: SSHAlgorithms.all"
                ],
                executeDiagnostics: [
                    "failure stage: execute",
                    "ssh stack: Citadel",
                    "request kind: \(requestKind)",
                    "algorithms: SSHAlgorithms.all"
                ]
            ) {
            case .success:
                continue
            case .failure(let failure):
                return .failure(RemoteAlertOperationError(message: failure.statusMessage))
            }
        }

        return await fetchRemoteAlertStatus(config: config)
    }

    static func removeCPUAlert(config: ServerConfig) async -> Result<RemoteAlertStatus, RemoteAlertOperationError> {
        switch await execute(
            config: config,
            script: makeRemoteAlertRemovalScript(),
            connectionDiagnostics: [
                "failure stage: connect",
                "ssh stack: Citadel",
                "request kind: remote-alert-remove",
                "algorithms: SSHAlgorithms.all"
            ],
            executeDiagnostics: [
                "failure stage: execute",
                "ssh stack: Citadel",
                "request kind: remote-alert-remove",
                "algorithms: SSHAlgorithms.all"
            ]
        ) {
        case .success:
            return await fetchRemoteAlertStatus(config: config)
        case .failure(let failure):
            return .failure(RemoteAlertOperationError(message: failure.statusMessage))
        }
    }

    static func sendTestBarkNotification(config: ServerConfig) async -> Result<String, RemoteAlertOperationError> {
        switch await execute(
            config: config,
            script: remoteAlertInstalledTestScript,
            connectionDiagnostics: [
                "failure stage: connect",
                "ssh stack: Citadel",
                "request kind: remote-alert-test",
                "algorithms: SSHAlgorithms.all"
            ],
            executeDiagnostics: [
                "failure stage: execute",
                "ssh stack: Citadel",
                "request kind: remote-alert-test",
                "algorithms: SSHAlgorithms.all"
            ]
        ) {
        case .success:
            return .success("远端告警测试通知已从目标服务器发出")
        case .failure(let failure):
            return .failure(RemoteAlertOperationError(message: failure.statusMessage))
        }
    }

    private static let fullStatsScript = """
    resolve_disk_source() {
      for mount_point in /overlay /; do
        source=""
        if command -v findmnt >/dev/null 2>&1; then
          source=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | awk 'NR==1 {print; exit}')
        fi
        [ -n "$source" ] || source=$(df -kP "$mount_point" 2>/dev/null | awk 'NR==2 {print $1}')
        case "$source" in
          /dev/*)
            printf '%s\n' "$source"
            return 0
            ;;
        esac
      done
      return 1
    }
    resolve_disk_device() {
      source=$(resolve_disk_source 2>/dev/null)
      [ -n "$source" ] || return 1
      resolved=$(readlink -f "$source" 2>/dev/null)
      if [ -n "$resolved" ] && [ -b "$resolved" ]; then
        source="$resolved"
      fi
      device=$(basename "$source")
      if [ -r "/sys/class/block/$device/stat" ]; then
        printf '%s\n' "$device"
        return 0
      fi
      if command -v lsblk >/dev/null 2>&1; then
        parent=$(lsblk -ndo PKNAME "$source" 2>/dev/null | awk 'NR==1 {print; exit}')
        if [ -n "$parent" ] && [ -r "/sys/class/block/$parent/stat" ]; then
          printf '%s\n' "$parent"
          return 0
        fi
      fi
      return 1
    }
    read_disk_counters() {
      device="$1"
      if [ -n "$device" ] && [ -r "/sys/class/block/$device/stat" ]; then
        awk '{print $3, $7; found=1; exit} END {if (!found) print "0 0"}' "/sys/class/block/$device/stat" 2>/dev/null
      else
        echo "0 0"
      fi
    }
    read_cpu_totals() {
      if [ -r /proc/stat ]; then
        awk '/^cpu / {idle=$5+$6; total=0; for (i=2; i<=NF; i++) total+=$i; printf "%.0f %.0f\\n", total, idle; found=1; exit} END {if (!found) print "0 0"}' /proc/stat 2>/dev/null
      else
        echo "0 0"
      fi
    }
    calculate_cpu_usage() {
      first_sample="$1"
      second_sample="$2"
      awk -v first="$first_sample" -v second="$second_sample" 'BEGIN {
        split(first, a, " ")
        split(second, b, " ")
        totald = (b[1] + 0) - (a[1] + 0)
        idled = (b[2] + 0) - (a[2] + 0)
        if (totald <= 0) { print "0"; exit }
        usage = ((totald - idled) * 100) / totald
        if (usage < 0) usage = 0
        if (usage > 100) usage = 100
        printf "%.1f\\n", usage
      }'
    }
    echo "=OS="; (if [ -f /etc/os-release ]; then . /etc/os-release; echo "${PRETTY_NAME:-$NAME}"; elif [ -f /etc/openwrt_release ]; then . /etc/openwrt_release; echo "${DISTRIB_DESCRIPTION:-$DISTRIB_ID $DISTRIB_RELEASE}"; else uname -sr; fi)
    echo "=HOSTNAME="; (hostname 2>/dev/null || uname -n 2>/dev/null || echo unknown)
    echo "=UPTIME="; (cat /proc/uptime 2>/dev/null | awk '{print $1}' || uptime 2>/dev/null || echo 0)
    echo "=CPU_INFO="; (awk -F: '/model name|Hardware|system type|machine/ {gsub(/^[ \\t]+/, "", $2); print $2; exit}' /proc/cpuinfo 2>/dev/null || uname -m 2>/dev/null || echo unknown)
    echo "=CPU_CORES="; (awk '/^processor/ {n++} END {print (n > 0 ? n : 1)}' /proc/cpuinfo 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    echo "=CPU_FREQ="; (if [ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ]; then awk '{printf "%.0f MHz\\n", $1/1000}' /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null; elif [ -r /proc/cpuinfo ]; then awk -F: '/cpu MHz/ {gsub(/^[ \\t]+/, "", $2); printf "%.0f MHz\\n", $2; found=1; exit} /clock/ {gsub(/^[ \\t]+/, "", $2); print $2; found=1; exit} END {if (!found) print "unknown"}' /proc/cpuinfo 2>/dev/null; else echo "unknown"; fi)
    echo "=WIFI_PHY_BANDS="; (if command -v iw >/dev/null 2>&1 && [ -d /sys/class/ieee80211 ]; then found=""; for p in /sys/class/ieee80211/phy*; do [ -d "$p" ] || continue; phy=$(basename "$p"); band=$(iw phy "$phy" info 2>/dev/null | awk '/Band 1:/{band="24g"} /Band 2:/{band="5g"} /Band 3:/{band="6g"} END{if(band) print band}'); [ -n "$band" ] || band="unknown"; printf "%s,%s;" "$phy" "$band"; found=1; done; if [ -n "$found" ]; then echo; else echo "none"; fi; else echo "none"; fi)
    echo "=TEMP_SENSORS="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/temp}; label=$(cat "$d/type" 2>/dev/null); [ -n "$label" ] || label=$(basename "$d"); label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/ieee80211/phy*/device/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/*}; phy=$(printf '%s' "$f" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; d=${f%/*}; resolved=$(readlink -f "$d" 2>/dev/null); v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; phy=$(printf '%s' "$resolved" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; if [ -n "$found" ]; then echo; else echo "unavailable"; fi)
    echo "=CPU_TEMP="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); [ -n "$v" ] || continue; type_file="${f%/temp}/type"; type=$(cat "$type_file" 2>/dev/null); case "$type" in *cpu*|*CPU*|*pkg*|*x86_pkg_temp*|*soc*|*SoC*|*cpu-thermal*) echo "$v"; found=1; break ;; esac; done; if [ -z "$found" ]; then for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; echo "$v"; found=1; break; done; fi; [ -n "$found" ] || echo "unknown")
    echo "=MEM="; (awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} /MemFree:/ {f=$2} END {avail=(a>0)?a:f; if (t>0) {u=t-avail; if (u<0) u=0; printf "%.0f %.0f %.0f\\n", t/1024, avail/1024, u/1024} else print "0 0 0"}' /proc/meminfo 2>/dev/null || echo "0 0 0")
    echo "=DISK="; (df -kP / 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "0 0 0 0% /"}')
    echo "=DISK_OVERLAY="; (df -kP /overlay 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "none"}')
    echo "=NSS_LOAD="; (if [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi 2>/dev/null; elif [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load 2>/dev/null; else echo "unavailable"; fi)
    echo "=NSS_FREQ="; (if [ -r /proc/sys/dev/nss/clock/current_freq ]; then awk '{v=$1+0; if (v > 1000000) printf "%.0f\\n", v/1000000; else if (v > 1000) printf "%.0f\\n", v/1000; else printf "%.0f\\n", v; found=1} END {if (!found) print "unknown"}' /proc/sys/dev/nss/clock/current_freq 2>/dev/null; else echo "unknown"; fi)
    echo "=LOADAVG="; (awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || uptime 2>/dev/null | awk -F'load average: ' 'NF > 1 {gsub(/,/, "", $2); split($2, a, " "); if (length(a) >= 3) print a[1], a[2], a[3]}' || echo "0 0 0")
    echo "=PSI_CPU="; (if [ -r /proc/pressure/cpu ]; then awk 'BEGIN{ORS=";"} {gsub(/;/, "", $0); print}' /proc/pressure/cpu 2>/dev/null; echo; else echo "unavailable"; fi)
    echo "=PSI_MEMORY="; (if [ -r /proc/pressure/memory ]; then awk 'BEGIN{ORS=";"} {gsub(/;/, "", $0); print}' /proc/pressure/memory 2>/dev/null; echo; else echo "unavailable"; fi)
    echo "=PSI_IO="; (if [ -r /proc/pressure/io ]; then awk 'BEGIN{ORS=";"} {gsub(/;/, "", $0); print}' /proc/pressure/io 2>/dev/null; echo; else echo "unavailable"; fi)
    CPU_SAMPLE_1=$(read_cpu_totals)
    NET_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    [ -n "$NET_IFACE" ] || NET_IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
    [ -n "$NET_IFACE" ] || NET_IFACE=$(awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $2; exit}' /proc/net/dev 2>/dev/null)
    DISK_DEVICE=$(resolve_disk_device 2>/dev/null)
    echo "=NET="; (if [ -n "$NET_IFACE" ]; then awk -F'[: ]+' -v iface="$NET_IFACE" 'NR > 2 && $2 == iface {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null; else echo "0 0"; fi)
    echo "=DISK_IO="; (read_disk_counters "$DISK_DEVICE")
    sleep 1
    CPU_SAMPLE_2=$(read_cpu_totals)
    echo "=NET2="; (if [ -n "$NET_IFACE" ]; then awk -F'[: ]+' -v iface="$NET_IFACE" 'NR > 2 && $2 == iface {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null; else echo "0 0"; fi)
    echo "=DISK_IO2="; (read_disk_counters "$DISK_DEVICE")
    echo "=CPU_USAGE="; (calculate_cpu_usage "$CPU_SAMPLE_1" "$CPU_SAMPLE_2")
    echo "=IS_ROUTER="; (if [ -f /etc/openwrt_release ] || ip link show br-lan >/dev/null 2>&1; then echo "yes"; else echo "no"; fi)
    echo "=CONNECTED_DEVICES="; (if [ -f /etc/openwrt_release ] || ip link show br-lan >/dev/null 2>&1; then cat /tmp/dhcp.leases 2>/dev/null | awk '{printf "%s,%s,%s;", $3, $2, $4}'; echo ""; else echo "none"; fi)
    echo "=WIFI_CLIENTS="; (if command -v iw >/dev/null 2>&1 && [ -d /sys/class/ieee80211 ]; then for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do phy=$(iw dev "$iface" info 2>/dev/null | awk '/wiphy/{print $2}'); band="unknown"; if [ -n "$phy" ]; then band=$(iw phy "phy$phy" info 2>/dev/null | awk '/Band 1:/{b="24g"} /Band 2:/{b="5g"} /Band 3:/{b="6g"} END{if(b) print b}'); fi; [ -z "$band" ] && band="unknown"; iw dev "$iface" station dump 2>/dev/null | awk -v b="$band" 'BEGIN{mac="";sig=""} /^Station /{if(mac!="") printf "%s,%s,%s;",mac,sig,b; mac=$2;sig=""} /signal:/{gsub(/[[][^]]*[]]/,"",$0); for(i=1;i<=NF;i++){if($i ~ /^-?[0-9]+$/){sig=$i;break}}} END{if(mac!="") printf "%s,%s,%s;",mac,sig,b}'; done; echo ""; else echo "none"; fi)
    exit 0
    """

    private static let dynamicStatsScript = """
    resolve_disk_source() {
      for mount_point in /overlay /; do
        source=""
        if command -v findmnt >/dev/null 2>&1; then
          source=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | awk 'NR==1 {print; exit}')
        fi
        [ -n "$source" ] || source=$(df -kP "$mount_point" 2>/dev/null | awk 'NR==2 {print $1}')
        case "$source" in
          /dev/*)
            printf '%s\n' "$source"
            return 0
            ;;
        esac
      done
      return 1
    }
    resolve_disk_device() {
      source=$(resolve_disk_source 2>/dev/null)
      [ -n "$source" ] || return 1
      resolved=$(readlink -f "$source" 2>/dev/null)
      if [ -n "$resolved" ] && [ -b "$resolved" ]; then
        source="$resolved"
      fi
      device=$(basename "$source")
      if [ -r "/sys/class/block/$device/stat" ]; then
        printf '%s\n' "$device"
        return 0
      fi
      if command -v lsblk >/dev/null 2>&1; then
        parent=$(lsblk -ndo PKNAME "$source" 2>/dev/null | awk 'NR==1 {print; exit}')
        if [ -n "$parent" ] && [ -r "/sys/class/block/$parent/stat" ]; then
          printf '%s\n' "$parent"
          return 0
        fi
      fi
      return 1
    }
    read_disk_counters() {
      device="$1"
      if [ -n "$device" ] && [ -r "/sys/class/block/$device/stat" ]; then
        awk '{print $3, $7; found=1; exit} END {if (!found) print "0 0"}' "/sys/class/block/$device/stat" 2>/dev/null
      else
        echo "0 0"
      fi
    }
    read_cpu_totals() {
      if [ -r /proc/stat ]; then
        awk '/^cpu / {idle=$5+$6; total=0; for (i=2; i<=NF; i++) total+=$i; printf "%.0f %.0f\\n", total, idle; found=1; exit} END {if (!found) print "0 0"}' /proc/stat 2>/dev/null
      else
        echo "0 0"
      fi
    }
    calculate_cpu_usage() {
      first_sample="$1"
      second_sample="$2"
      awk -v first="$first_sample" -v second="$second_sample" 'BEGIN {
        split(first, a, " ")
        split(second, b, " ")
        totald = (b[1] + 0) - (a[1] + 0)
        idled = (b[2] + 0) - (a[2] + 0)
        if (totald <= 0) { print "0"; exit }
        usage = ((totald - idled) * 100) / totald
        if (usage < 0) usage = 0
        if (usage > 100) usage = 100
        printf "%.1f\\n", usage
      }'
    }
    echo "=UPTIME="; (cat /proc/uptime 2>/dev/null | awk '{print $1}' || uptime 2>/dev/null || echo 0)
    echo "=WIFI_PHY_BANDS="; (if command -v iw >/dev/null 2>&1 && [ -d /sys/class/ieee80211 ]; then found=""; for p in /sys/class/ieee80211/phy*; do [ -d "$p" ] || continue; phy=$(basename "$p"); band=$(iw phy "$phy" info 2>/dev/null | awk '/Band 1:/{band="24g"} /Band 2:/{band="5g"} /Band 3:/{band="6g"} END{if(band) print band}'); [ -n "$band" ] || band="unknown"; printf "%s,%s;" "$phy" "$band"; found=1; done; if [ -n "$found" ]; then echo; else echo "none"; fi; else echo "none"; fi)
    echo "=TEMP_SENSORS="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/temp}; label=$(cat "$d/type" 2>/dev/null); [ -n "$label" ] || label=$(basename "$d"); label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/ieee80211/phy*/device/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; d=${f%/*}; phy=$(printf '%s' "$f" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; for f in /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; d=${f%/*}; resolved=$(readlink -f "$d" 2>/dev/null); v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; b=$(basename "$f"); sensor=${b%_input}; label=$(cat "$d/${sensor}_label" 2>/dev/null); [ -n "$label" ] || label=$(cat "$d/name" 2>/dev/null); [ -n "$label" ] || label="$sensor"; phy=$(printf '%s' "$resolved" | awk 'match($0,/phy[0-9]+/){print substr($0, RSTART, RLENGTH); exit}'); [ -n "$phy" ] && label="$label-$phy"; label=$(printf '%s' "$label" | tr ';,' '__'); printf "%s,%s;" "$label" "$v"; found=1; done; if [ -n "$found" ]; then echo; else echo "unavailable"; fi)
    echo "=CPU_TEMP="; (found=""; for f in /sys/class/thermal/thermal_zone*/temp; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); [ -n "$v" ] || continue; type_file="${f%/temp}/type"; type=$(cat "$type_file" 2>/dev/null); case "$type" in *cpu*|*CPU*|*pkg*|*x86_pkg_temp*|*soc*|*SoC*|*cpu-thermal*) echo "$v"; found=1; break ;; esac; done; if [ -z "$found" ]; then for f in /sys/class/thermal/thermal_zone*/temp /sys/class/hwmon/hwmon*/temp*_input; do [ -r "$f" ] || continue; v=$(cat "$f" 2>/dev/null); case "$v" in ''|*[!0-9.]* ) continue ;; esac; echo "$v"; found=1; break; done; fi; [ -n "$found" ] || echo "unknown")
    echo "=MEM="; (awk '/MemTotal:/ {t=$2} /MemAvailable:/ {a=$2} /MemFree:/ {f=$2} END {avail=(a>0)?a:f; if (t>0) {u=t-avail; if (u<0) u=0; printf "%.0f %.0f %.0f\\n", t/1024, avail/1024, u/1024} else print "0 0 0"}' /proc/meminfo 2>/dev/null || echo "0 0 0")
    echo "=DISK="; (df -kP / 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "0 0 0 0% /"}')
    echo "=DISK_OVERLAY="; (df -kP /overlay 2>/dev/null | awk 'NR==2 {printf "%.0f %.0f %.0f %s %s\\n", $2/1024, $3/1024, $4/1024, $5, $6; found=1} END {if (!found) print "none"}')
    echo "=NSS_LOAD="; (if [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi 2>/dev/null; elif [ -r /sys/kernel/debug/qca-nss-drv/stats/cpu_load ]; then awk '/^Core / {core=$2; gsub(":", "", core); next} /^[[:space:]]*[0-9]+%/ && core != "" {min=$1; avg=$2; max=$3; gsub(/%/, "", min); gsub(/%/, "", avg); gsub(/%/, "", max); printf "%s,%s,%s,%s;", core, min, avg, max; found=1; core=""} END {if (!found) print "unavailable"; else print ""}' /sys/kernel/debug/qca-nss-drv/stats/cpu_load 2>/dev/null; else echo "unavailable"; fi)
    echo "=NSS_FREQ="; (if [ -r /proc/sys/dev/nss/clock/current_freq ]; then awk '{v=$1+0; if (v > 1000000) printf "%.0f\\n", v/1000000; else if (v > 1000) printf "%.0f\\n", v/1000; else printf "%.0f\\n", v; found=1} END {if (!found) print "unknown"}' /proc/sys/dev/nss/clock/current_freq 2>/dev/null; else echo "unknown"; fi)
    echo "=LOADAVG="; (awk '{print $1, $2, $3}' /proc/loadavg 2>/dev/null || uptime 2>/dev/null | awk -F'load average: ' 'NF > 1 {gsub(/,/, "", $2); split($2, a, " "); if (length(a) >= 3) print a[1], a[2], a[3]}' || echo "0 0 0")
    echo "=PSI_CPU="; (if [ -r /proc/pressure/cpu ]; then awk 'BEGIN{ORS=";"} {gsub(/;/, "", $0); print}' /proc/pressure/cpu 2>/dev/null; echo; else echo "unavailable"; fi)
    echo "=PSI_MEMORY="; (if [ -r /proc/pressure/memory ]; then awk 'BEGIN{ORS=";"} {gsub(/;/, "", $0); print}' /proc/pressure/memory 2>/dev/null; echo; else echo "unavailable"; fi)
    echo "=PSI_IO="; (if [ -r /proc/pressure/io ]; then awk 'BEGIN{ORS=";"} {gsub(/;/, "", $0); print}' /proc/pressure/io 2>/dev/null; echo; else echo "unavailable"; fi)
    CPU_SAMPLE_1=$(read_cpu_totals)
    NET_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
    [ -n "$NET_IFACE" ] || NET_IFACE=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
    [ -n "$NET_IFACE" ] || NET_IFACE=$(awk -F'[: ]+' 'NR > 2 && $2 != "lo" {print $2; exit}' /proc/net/dev 2>/dev/null)
    DISK_DEVICE=$(resolve_disk_device 2>/dev/null)
    echo "=NET="; (if [ -n "$NET_IFACE" ]; then awk -F'[: ]+' -v iface="$NET_IFACE" 'NR > 2 && $2 == iface {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null; else echo "0 0"; fi)
    echo "=DISK_IO="; (read_disk_counters "$DISK_DEVICE")
    sleep 1
    CPU_SAMPLE_2=$(read_cpu_totals)
    echo "=NET2="; (if [ -n "$NET_IFACE" ]; then awk -F'[: ]+' -v iface="$NET_IFACE" 'NR > 2 && $2 == iface {print $3, $11; found=1; exit} END {if (!found) print "0 0"}' /proc/net/dev 2>/dev/null; else echo "0 0"; fi)
    echo "=DISK_IO2="; (read_disk_counters "$DISK_DEVICE")
    echo "=CPU_USAGE="; (calculate_cpu_usage "$CPU_SAMPLE_1" "$CPU_SAMPLE_2")
    echo "=IS_ROUTER="; (if [ -f /etc/openwrt_release ] || ip link show br-lan >/dev/null 2>&1; then echo "yes"; else echo "no"; fi)
    echo "=CONNECTED_DEVICES="; (if [ -f /etc/openwrt_release ] || ip link show br-lan >/dev/null 2>&1; then cat /tmp/dhcp.leases 2>/dev/null | awk '{printf "%s,%s,%s;", $3, $2, $4}'; echo ""; else echo "none"; fi)
    echo "=WIFI_CLIENTS="; (if command -v iw >/dev/null 2>&1 && [ -d /sys/class/ieee80211 ]; then for iface in $(iw dev 2>/dev/null | awk '/Interface/{print $2}'); do phy=$(iw dev "$iface" info 2>/dev/null | awk '/wiphy/{print $2}'); band="unknown"; if [ -n "$phy" ]; then band=$(iw phy "phy$phy" info 2>/dev/null | awk '/Band 1:/{b="24g"} /Band 2:/{b="5g"} /Band 3:/{b="6g"} END{if(b) print b}'); fi; [ -z "$band" ] && band="unknown"; iw dev "$iface" station dump 2>/dev/null | awk -v b="$band" 'BEGIN{mac="";sig=""} /^Station /{if(mac!="") printf "%s,%s,%s;",mac,sig,b; mac=$2;sig=""} /signal:/{gsub(/[[][^]]*[]]/,"",$0); for(i=1;i<=NF;i++){if($i ~ /^-?[0-9]+$/){sig=$i;break}}} END{if(mac!="") printf "%s,%s,%s;",mac,sig,b}'; done; echo ""; else echo "none"; fi)
    exit 0
    """

    private static let remoteAlertStatusScript = """
    ALERT_DIR="$HOME/.ios-monitor"
    SCRIPT_PATH="$ALERT_DIR/cpu_alert.sh"
    ENV_PATH="$ALERT_DIR/cpu_alert.env"
    INSTALLED="no"
    MESSAGE="未在服务器上安装远端告警"
    RULES=""

    append_rule() {
      if [ -z "$RULES" ]; then
        RULES="$1"
      else
        RULES="$RULES, $1"
      fi
    }

    if [ -f "$SCRIPT_PATH" ] && (crontab -l 2>/dev/null || true) | grep -F "$SCRIPT_PATH" >/dev/null 2>&1; then
      INSTALLED="yes"
      if [ -r "$ENV_PATH" ]; then
        . "$ENV_PATH"
        if [ "${CPU_USAGE_ENABLED:-0}" = "1" ]; then
          append_rule "CPU >= ${CPU_USAGE_THRESHOLD:-90}%"
        elif [ -n "${CPU_THRESHOLD:-}" ]; then
          append_rule "CPU >= ${CPU_THRESHOLD}%"
        fi
        [ "${MEMORY_USAGE_ENABLED:-0}" = "1" ] && append_rule "内存 >= ${MEMORY_USAGE_THRESHOLD:-90}%"
        [ "${PSI_CPU_ENABLED:-0}" = "1" ] && append_rule "CPU PSI(avg10) >= ${PSI_CPU_THRESHOLD:-5}%"
        [ "${PSI_MEMORY_ENABLED:-0}" = "1" ] && append_rule "内存 PSI(avg10) >= ${PSI_MEMORY_THRESHOLD:-5}%"
        [ "${PSI_IO_ENABLED:-0}" = "1" ] && append_rule "IO PSI(avg10) >= ${PSI_IO_THRESHOLD:-5}%"
        if [ "${WEBSITE_ENABLED:-0}" = "1" ]; then
          index=1
          while [ "$index" -le "${WEBSITE_TARGET_COUNT:-0}" ]; do
            eval "WEBSITE_TARGET=\\${WEBSITE_TARGET_${index}:-}"
            [ -n "${WEBSITE_TARGET:-}" ] && append_rule "网站不可达: ${WEBSITE_TARGET}"
            index=$((index + 1))
          done
          if [ "${WEBSITE_TARGET_COUNT:-0}" = "0" ] && [ -n "${WEBSITE_URL:-}" ]; then
            append_rule "网站不可达: ${WEBSITE_URL}"
          fi
        fi
      fi
      if [ -n "${RULES:-}" ]; then
        MESSAGE="已启用规则: $RULES"
      else
        MESSAGE="已启用远端告警"
      fi
    fi
    echo "=ALERT_INSTALLED="
    echo "$INSTALLED"
    echo "=SCRIPT_PATH="
    echo "$SCRIPT_PATH"
    echo "=SCHEDULE="
    if [ "$INSTALLED" = "yes" ]; then echo "cron every minute"; else echo "not installed"; fi
    echo "=MESSAGE="
    echo "$MESSAGE"
    echo "=REMOTE_RULES="
    echo "$RULES"
    echo "=HAS_CONFIG="
    if [ -f "$ENV_PATH" ]; then echo "yes"; else echo "no"; fi
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
        var disk1: (readSectors: Double, writeSectors: Double)?
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
            } else if line == "=LOADAVG=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyLoadAverage(from: lines[i + 1], to: &stats)
            } else if line == "=PSI_CPU=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyPressureValues(from: lines[i + 1], resource: .cpu, to: &stats)
            } else if line == "=PSI_MEMORY=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyPressureValues(from: lines[i + 1], resource: .memory, to: &stats)
            } else if line == "=PSI_IO=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyPressureValues(from: lines[i + 1], resource: .io, to: &stats)
            } else if line == "=CPU_USAGE=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.cpuUsage = parseCPUUsage(from: lines[i + 1])
            } else if line == "=NET=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                net1 = parseNetCounters(from: lines[i + 1])
            } else if line == "=DISK_IO=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                disk1 = parseDiskCounters(from: lines[i + 1])
            } else if line == "=NET2=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNetworkSpeeds(firstSample: net1, secondLine: lines[i + 1], to: &stats)
            } else if line == "=DISK_IO2=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyDiskIOSpeeds(firstSample: disk1, secondLine: lines[i + 1], to: &stats)
            } else if line == "=IS_ROUTER=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                stats.routerInfo.isRouter = lines[i + 1].trimmingCharacters(in: .whitespaces) == "yes"
            } else if line == "=CONNECTED_DEVICES=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                if stats.routerInfo.isRouter {
                    stats.routerInfo.connectedDevices = parseConnectedDevices(from: lines[i + 1])
                }
            } else if line == "=WIFI_CLIENTS=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                if stats.routerInfo.isRouter {
                    applyWiFiClients(from: lines[i + 1], to: &stats.routerInfo)
                }
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
            "=LOADAVG=",
            "=PSI_CPU=",
            "=PSI_MEMORY=",
            "=PSI_IO=",
            "=CPU_USAGE=",
            "=NET=",
            "=DISK_IO=",
            "=NET2=",
            "=DISK_IO2="
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
        var disk1: (readSectors: Double, writeSectors: Double)?
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
            } else if line == "=LOADAVG=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyLoadAverage(from: lines[i + 1], to: &dynamic)
            } else if line == "=PSI_CPU=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyPressureValues(from: lines[i + 1], resource: .cpu, to: &dynamic)
            } else if line == "=PSI_MEMORY=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyPressureValues(from: lines[i + 1], resource: .memory, to: &dynamic)
            } else if line == "=PSI_IO=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyPressureValues(from: lines[i + 1], resource: .io, to: &dynamic)
            } else if line == "=CPU_USAGE=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                dynamic.cpuUsage = parseCPUUsage(from: lines[i + 1])
            } else if line == "=NET=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                net1 = parseNetCounters(from: lines[i + 1])
            } else if line == "=DISK_IO=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                disk1 = parseDiskCounters(from: lines[i + 1])
            } else if line == "=NET2=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyNetworkSpeeds(firstSample: net1, secondLine: lines[i + 1], to: &dynamic)
            } else if line == "=DISK_IO2=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                applyDiskIOSpeeds(firstSample: disk1, secondLine: lines[i + 1], to: &dynamic)
            } else if line == "=IS_ROUTER=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                dynamic.routerInfo.isRouter = lines[i + 1].trimmingCharacters(in: .whitespaces) == "yes"
            } else if line == "=CONNECTED_DEVICES=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                if dynamic.routerInfo.isRouter {
                    dynamic.routerInfo.connectedDevices = parseConnectedDevices(from: lines[i + 1])
                }
            } else if line == "=WIFI_CLIENTS=" && i + 1 < lines.count {
                seenMarkers.insert(line)
                if dynamic.routerInfo.isRouter {
                    applyWiFiClients(from: lines[i + 1], to: &dynamic.routerInfo)
                }
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
            "=LOADAVG=",
            "=PSI_CPU=",
            "=PSI_MEMORY=",
            "=PSI_IO=",
            "=CPU_USAGE=",
            "=NET=",
            "=DISK_IO=",
            "=NET2=",
            "=DISK_IO2="
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

    private static func applyLoadAverage(from line: String, to stats: inout ServerStats) {
        let load = parseLoadAverage(from: line)
        stats.loadAverage1m = load.oneMinute
        stats.loadAverage5m = load.fiveMinute
        stats.loadAverage15m = load.fifteenMinute
    }

    private static func applyLoadAverage(from line: String, to dynamic: inout ServerDynamicInfo) {
        let load = parseLoadAverage(from: line)
        dynamic.loadAverage1m = load.oneMinute
        dynamic.loadAverage5m = load.fiveMinute
        dynamic.loadAverage15m = load.fifteenMinute
    }

    private enum PressureResource {
        case cpu
        case memory
        case io
    }

    private static func applyPressureValues(from line: String, resource: PressureResource, to stats: inout ServerStats) {
        let parsed = parsePressureMetrics(from: line)

        switch resource {
        case .cpu:
            stats.pressure.cpuSomeAvg10 = parsed.someAvg10
        case .memory:
            stats.pressure.memorySomeAvg10 = parsed.someAvg10
            stats.pressure.memoryFullAvg10 = parsed.fullAvg10
        case .io:
            stats.pressure.ioSomeAvg10 = parsed.someAvg10
            stats.pressure.ioFullAvg10 = parsed.fullAvg10
        }
    }

    private static func applyPressureValues(from line: String, resource: PressureResource, to dynamic: inout ServerDynamicInfo) {
        let parsed = parsePressureMetrics(from: line)

        switch resource {
        case .cpu:
            dynamic.pressure.cpuSomeAvg10 = parsed.someAvg10
        case .memory:
            dynamic.pressure.memorySomeAvg10 = parsed.someAvg10
            dynamic.pressure.memoryFullAvg10 = parsed.fullAvg10
        case .io:
            dynamic.pressure.ioSomeAvg10 = parsed.someAvg10
            dynamic.pressure.ioFullAvg10 = parsed.fullAvg10
        }
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

    private static func parseLoadAverage(from line: String) -> (oneMinute: Double?, fiveMinute: Double?, fifteenMinute: Double?) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return (
            oneMinute: parts.count > 0 ? Double(parts[0]) : nil,
            fiveMinute: parts.count > 1 ? Double(parts[1]) : nil,
            fifteenMinute: parts.count > 2 ? Double(parts[2]) : nil
        )
    }

    private static func parsePressureMetrics(from line: String) -> (someAvg10: Double?, fullAvg10: Double?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "unavailable" else {
            return (nil, nil)
        }

        var someAvg10: Double?
        var fullAvg10: Double?

        for segment in trimmed.split(separator: ";") {
            let entry = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !entry.isEmpty else { continue }

            if entry.hasPrefix("some ") {
                someAvg10 = parsePressureAvg10(from: entry)
            } else if entry.hasPrefix("full ") {
                fullAvg10 = parsePressureAvg10(from: entry)
            }
        }

        return (someAvg10, fullAvg10)
    }

    private static func parsePressureAvg10(from entry: String) -> Double? {
        for token in entry.split(separator: " ") where token.hasPrefix("avg10=") {
            return Double(String(token).replacingOccurrences(of: "avg10=", with: ""))
        }
        return nil
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
        // Only match exact "phyN" (e.g. phy0, phy1), not phyaN or other variants
        // label has already been normalized (lowercased, dashes/underscores removed)
        for (phy, band) in wifiPhyBands {
            guard phy.hasPrefix("phy"), !phy.isEmpty else { continue }
            guard let range = label.range(of: phy) else { continue }
            let afterIndex = range.upperBound
            // phyN must be at end of label, or followed by a non-digit character
            if afterIndex == label.endIndex || !label[afterIndex].isNumber {
                return band
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

    private static func parseDiskCounters(from line: String) -> (readSectors: Double, writeSectors: Double)? {
        let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return (
            readSectors: Double(parts[0]) ?? 0,
            writeSectors: Double(parts[1]) ?? 0
        )
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

    private static func applyDiskIOSpeeds(
        firstSample: (readSectors: Double, writeSectors: Double)?,
        secondLine: String,
        to stats: inout ServerStats
    ) {
        guard let firstSample,
              let secondSample = parseDiskCounters(from: secondLine) else {
            return
        }

        let readBytes = max(0, secondSample.readSectors - firstSample.readSectors) * 512
        let writeBytes = max(0, secondSample.writeSectors - firstSample.writeSectors) * 512
        stats.diskReadSpeed = formatSpeed(readBytes)
        stats.diskWriteSpeed = formatSpeed(writeBytes)
    }

    private static func applyDiskIOSpeeds(
        firstSample: (readSectors: Double, writeSectors: Double)?,
        secondLine: String,
        to dynamic: inout ServerDynamicInfo
    ) {
        guard let firstSample,
              let secondSample = parseDiskCounters(from: secondLine) else {
            return
        }

        let readBytes = max(0, secondSample.readSectors - firstSample.readSectors) * 512
        let writeBytes = max(0, secondSample.writeSectors - firstSample.writeSectors) * 512
        dynamic.diskReadSpeed = formatSpeed(readBytes)
        dynamic.diskWriteSpeed = formatSpeed(writeBytes)
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

    // MARK: - Router / Connected Devices

    /// Parses DHCP lease entries: "ip,mac,hostname;ip,mac,hostname;..."
    private static func parseConnectedDevices(from line: String) -> [ConnectedDevice] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "none" else { return [] }

        var devices: [ConnectedDevice] = []
        var seen = Set<String>()

        for entry in trimmed.split(separator: ";") {
            let parts = entry.split(separator: ",", maxSplits: 2)
            guard parts.count >= 2 else { continue }

            let ip = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let mac = String(parts[1]).trimmingCharacters(in: .whitespaces).uppercased()
            let hostname = parts.count >= 3
                ? String(parts[2]).trimmingCharacters(in: .whitespaces)
                : ""

            guard !mac.isEmpty, !seen.contains(mac) else { continue }
            seen.insert(mac)

            devices.append(ConnectedDevice(
                ip: ip,
                mac: mac,
                hostname: hostname,
                connectionType: .unknown,
                signalDBm: nil
            ))
        }

        return devices
    }

    /// Parses WiFi station dump: "mac,signal,band;mac,signal,band;..."
    /// Merges WiFi info (connection type + signal) into existing DHCP devices, or adds new entries.
    private static func applyWiFiClients(from line: String, to routerInfo: inout RouterInfo) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "none" else {
            // If no WiFi data, all existing devices without WiFi info are assumed wired
            for i in routerInfo.connectedDevices.indices {
                if routerInfo.connectedDevices[i].connectionType == .unknown {
                    routerInfo.connectedDevices[i].connectionType = .wired
                }
            }
            return
        }

        var wifiMACs = Set<String>()

        for entry in trimmed.split(separator: ";") {
            let parts = entry.split(separator: ",", maxSplits: 2)
            guard parts.count >= 1 else { continue }

            let mac = String(parts[0]).trimmingCharacters(in: .whitespaces).uppercased()
            guard !mac.isEmpty else { continue }

            let signal: Int? = parts.count >= 2
                ? Int(String(parts[1]).trimmingCharacters(in: .whitespaces))
                : nil

            let bandStr = parts.count >= 3
                ? String(parts[2]).trimmingCharacters(in: .whitespaces).lowercased()
                : "unknown"

            let connectionType: ConnectedDeviceConnectionType
            switch bandStr {
            case "24g": connectionType = .wifi24
            case "5g": connectionType = .wifi5
            default: connectionType = .unknown
            }

            wifiMACs.insert(mac)

            if let idx = routerInfo.connectedDevices.firstIndex(where: { $0.mac == mac }) {
                routerInfo.connectedDevices[idx].connectionType = connectionType
                routerInfo.connectedDevices[idx].signalDBm = signal
            } else {
                routerInfo.connectedDevices.append(ConnectedDevice(
                    ip: "",
                    mac: mac,
                    hostname: "",
                    connectionType: connectionType,
                    signalDBm: signal
                ))
            }
        }

        // Devices not seen in WiFi station dump are wired
        for i in routerInfo.connectedDevices.indices {
            if routerInfo.connectedDevices[i].connectionType == .unknown
                && !wifiMACs.contains(routerInfo.connectedDevices[i].mac) {
                routerInfo.connectedDevices[i].connectionType = .wired
            }
        }
    }

    private static func parseRemoteAlertStatus(output: String) -> RemoteAlertStatus {
        let fields = parseMarkerOutput(output)
        let installed = fields["ALERT_INSTALLED"] == "yes"
        let remoteRuleDescriptions = parseRemoteRuleDescriptions(from: fields["REMOTE_RULES"])
        return RemoteAlertStatus(
            isInstalled: installed,
            scriptPath: fields["SCRIPT_PATH"] ?? "~/.ios-monitor/cpu_alert.sh",
            scheduleDescription: fields["SCHEDULE"] ?? (installed ? "cron every minute" : "not installed"),
            remoteRuleDescriptions: remoteRuleDescriptions,
            lastCheckedAt: Date(),
            lastUpdatedAt: nil,
            lastMessage: fields["MESSAGE"] ?? (installed ? "已启用远端告警" : "未在服务器上安装远端告警"),
            lastError: nil
        )
    }

    private static func parseRemoteRuleDescriptions(from raw: String?) -> [String] {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        return trimmed
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func parseMarkerOutput(_ output: String) -> [String: String] {
        var values: [String: String] = [:]
        var pendingKey: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("="), trimmed.hasSuffix("="), trimmed.count > 2 {
                pendingKey = String(trimmed.dropFirst().dropLast())
                continue
            }

            if let key = pendingKey {
                values[key] = trimmed
                pendingKey = nil
            }
        }

        return values
    }

    private static func makeRemoteAlertDeploymentCommands(config: ServerConfig, barkBaseURL: String) -> [String] {
        let alertConfiguration = config.alertConfiguration
        let cooldownSeconds = max(1, alertConfiguration.cooldownMinutes) * 60
        let hostLabel = (config.name.isEmpty ? config.host : config.name).trimmingCharacters(in: .whitespacesAndNewlines)
        let safeHostLabel = hostLabel.isEmpty ? config.host : hostLabel
        let safeHostValue = normalizedHostValue(from: config)
        let websiteTargets = AlertConfiguration.normalizedWebsiteTargets(alertConfiguration.websiteTargets)
        let websiteTargetEnvLines = websiteTargets.enumerated().map { index, target in
            "WEBSITE_TARGET_\(index + 1)=\(shellQuoted(target))"
        }.joined(separator: "\n")
        let envBody = """
        BARK_URL=\(shellQuoted(barkBaseURL))
        COOLDOWN_SECONDS='\(cooldownSeconds)'
        HOST_LABEL=\(shellQuoted(safeHostLabel))
        HOST_VALUE=\(shellQuoted(safeHostValue))
        CPU_USAGE_ENABLED='\(shellBool(alertConfiguration.cpuUsageEnabled))'
        CPU_USAGE_THRESHOLD='\(alertConfiguration.cpuUsageThreshold)'
        MEMORY_USAGE_ENABLED='\(shellBool(alertConfiguration.memoryUsageEnabled))'
        MEMORY_USAGE_THRESHOLD='\(alertConfiguration.memoryUsageThreshold)'
        PSI_CPU_ENABLED='\(shellBool(alertConfiguration.psiCPUEnabled))'
        PSI_CPU_THRESHOLD='\(alertConfiguration.psiCPUThreshold)'
        PSI_MEMORY_ENABLED='\(shellBool(alertConfiguration.psiMemoryEnabled))'
        PSI_MEMORY_THRESHOLD='\(alertConfiguration.psiMemoryThreshold)'
        PSI_IO_ENABLED='\(shellBool(alertConfiguration.psiIOEnabled))'
        PSI_IO_THRESHOLD='\(alertConfiguration.psiIOThreshold)'
        WEBSITE_ENABLED='\(shellBool(alertConfiguration.websiteEnabled))'
        WEBSITE_TARGET_COUNT='\(websiteTargets.count)'
        \(websiteTargetEnvLines)
        """
        let scriptFiles: [(name: String, body: String)] = [
            ("alert_transport.sh", remoteAlertTransportScript),
            ("alert_cpu.sh", remoteAlertCPUReaderScript),
            ("alert_memory.sh", remoteAlertMemoryReaderScript),
            ("alert_psi.sh", remoteAlertPSIReaderScript),
            ("alert_website.sh", remoteAlertWebsiteCheckerScript),
            ("cpu_alert.sh", remoteAlertRunnerScript)
        ]

        var commands: [String] = [
            """
            set -eu
            ALERT_DIR="$HOME/.ios-monitor"
            SCRIPT_PATH="$ALERT_DIR/cpu_alert.sh"
            ENV_PATH="$ALERT_DIR/cpu_alert.env"
            mkdir -p "$ALERT_DIR"
            if ! command -v crontab >/dev/null 2>&1; then
              echo "crontab command is unavailable"
              exit 1
            fi
            if command -v curl >/dev/null 2>&1; then
              :
            elif command -v wget >/dev/null 2>&1; then
              :
            elif command -v uclient-fetch >/dev/null 2>&1; then
              :
            else
              echo "curl, wget, or uclient-fetch is required for Bark notifications"
              exit 1
            fi
            : > "$SCRIPT_PATH"
            """
        ]

        for (index, file) in scriptFiles.enumerated() {
            let delimiter = "IOS_MONITOR_REMOTE_ALERT_\(index)"
            commands.append(
                """
                set -eu
                ALERT_DIR="$HOME/.ios-monitor"
                FILE_PATH="$ALERT_DIR/\(file.name)"
                cat > "$FILE_PATH" <<'\(delimiter)'
                \(file.body)
                \(delimiter)
                chmod 700 "$FILE_PATH"
                """
            )
        }

        commands.append(
            """
            set -eu
            ALERT_DIR="$HOME/.ios-monitor"
            ENV_PATH="$ALERT_DIR/cpu_alert.env"
            cat > "$ENV_PATH" <<'IOS_MONITOR_REMOTE_ALERT_ENV'
            \(envBody)
            IOS_MONITOR_REMOTE_ALERT_ENV
            chmod 600 "$ENV_PATH"
            """
        )

        commands.append(
            """
            set -eu
            ALERT_DIR="$HOME/.ios-monitor"
            SCRIPT_PATH="$ALERT_DIR/cpu_alert.sh"
            CURRENT_CRON=$(crontab -l 2>/dev/null || true)
            FILTERED_CRON=$(printf '%s\\n' "$CURRENT_CRON" | grep -Fv "$SCRIPT_PATH" || true)
            NEW_ENTRY="* * * * * /bin/sh \\"$SCRIPT_PATH\\" >/dev/null 2>&1"
            if [ -n "$FILTERED_CRON" ]; then
              printf '%s\\n%s\\n' "$FILTERED_CRON" "$NEW_ENTRY" | crontab -
            else
              printf '%s\\n' "$NEW_ENTRY" | crontab -
            fi
            """
        )

        return commands
    }

    private static func makeRemoteAlertRemovalScript() -> String {
        """
        set -eu
        ALERT_DIR="$HOME/.ios-monitor"
        SCRIPT_PATH="$ALERT_DIR/cpu_alert.sh"
        TRANSPORT_PATH="$ALERT_DIR/alert_transport.sh"
        CPU_PATH="$ALERT_DIR/alert_cpu.sh"
        MEMORY_PATH="$ALERT_DIR/alert_memory.sh"
        PSI_PATH="$ALERT_DIR/alert_psi.sh"
        WEBSITE_PATH="$ALERT_DIR/alert_website.sh"
        ENV_PATH="$ALERT_DIR/cpu_alert.env"
        STATE_PATH="$ALERT_DIR/cpu_alert.state"

        if command -v crontab >/dev/null 2>&1; then
          CURRENT_CRON=$(crontab -l 2>/dev/null || true)
          FILTERED_CRON=$(printf '%s\\n' "$CURRENT_CRON" | grep -Fv "$SCRIPT_PATH" || true)
          if [ -n "$FILTERED_CRON" ]; then
            printf '%s\\n' "$FILTERED_CRON" | crontab -
          else
            crontab -r 2>/dev/null || true
          fi
        fi

        rm -f "$SCRIPT_PATH" "$TRANSPORT_PATH" "$CPU_PATH" "$MEMORY_PATH" "$PSI_PATH" "$WEBSITE_PATH" "$ENV_PATH" "$STATE_PATH"
        rmdir "$ALERT_DIR" 2>/dev/null || true
        exit 0
        """
    }

    private static let remoteAlertInstalledTestScript = """
    set -eu
    ALERT_DIR="$HOME/.ios-monitor"
    SCRIPT_PATH="$ALERT_DIR/cpu_alert.sh"
    TRANSPORT_PATH="$ALERT_DIR/alert_transport.sh"
    CPU_PATH="$ALERT_DIR/alert_cpu.sh"
    MEMORY_PATH="$ALERT_DIR/alert_memory.sh"
    PSI_PATH="$ALERT_DIR/alert_psi.sh"
    WEBSITE_PATH="$ALERT_DIR/alert_website.sh"
    ENV_PATH="$ALERT_DIR/cpu_alert.env"

    if [ ! -r "$SCRIPT_PATH" ]; then
      echo "remote alert script is not installed"
      exit 1
    fi

    if [ ! -r "$ENV_PATH" ]; then
      echo "remote alert configuration is missing"
      exit 1
    fi

    for helper in "$TRANSPORT_PATH" "$CPU_PATH" "$MEMORY_PATH" "$PSI_PATH" "$WEBSITE_PATH"; do
      if [ ! -r "$helper" ]; then
        echo "remote helper script is missing: $helper"
        exit 1
      fi
    done

    /bin/sh "$SCRIPT_PATH" --test
    """

    private static var remoteAlertRunnerScript: String {
        """
        #!/bin/sh
        set -eu

        ALERT_DIR="${HOME}/.ios-monitor"
        TRANSPORT_PATH="$ALERT_DIR/alert_transport.sh"
        CPU_PATH="$ALERT_DIR/alert_cpu.sh"
        MEMORY_PATH="$ALERT_DIR/alert_memory.sh"
        PSI_PATH="$ALERT_DIR/alert_psi.sh"
        WEBSITE_PATH="$ALERT_DIR/alert_website.sh"
        ENV_PATH="$ALERT_DIR/cpu_alert.env"
        STATE_PATH="$ALERT_DIR/cpu_alert.state"

        [ -r "$ENV_PATH" ] || exit 1
        . "$ENV_PATH"

        [ -n "${HOST_LABEL:-}" ] || HOST_LABEL="${HOST_VALUE:-unknown}"
        [ -n "${HOST_VALUE:-}" ] || HOST_VALUE="${HOST_LABEL:-unknown}"

        for helper in "$TRANSPORT_PATH" "$CPU_PATH" "$MEMORY_PATH" "$PSI_PATH" "$WEBSITE_PATH"; do
          if [ ! -r "$helper" ]; then
            echo "missing helper script: $helper" >&2
            exit 1
          fi
          . "$helper"
        done

        title_for_alert() {
          printf '%s 告警' "$HOST_LABEL"
        }

        should_send_again() {
          previous_state="$1"
          previous_sent="$2"
          if [ "$previous_state" != "alert" ]; then
            return 0
          fi
          [ $((NOW - previous_sent)) -ge "${COOLDOWN_SECONDS:-600}" ]
        }

        if [ "${1:-}" = "--test" ]; then
          SUMMARY="远端告警脚本可用"
          DETAILS=""
          if [ "${CPU_USAGE_ENABLED:-0}" = "1" ]; then
            CPU_USAGE=$(fetch_cpu_usage)
            DETAILS="$DETAILS CPU=${CPU_USAGE}%"
          fi
          if [ "${MEMORY_USAGE_ENABLED:-0}" = "1" ]; then
            MEMORY_USAGE=$(fetch_memory_usage)
            DETAILS="$DETAILS MEM=${MEMORY_USAGE}%"
          fi
          if [ "${PSI_CPU_ENABLED:-0}" = "1" ]; then
            PSI_CPU=$(fetch_psi_avg10 cpu)
            DETAILS="$DETAILS CPU_PSI=${PSI_CPU}%"
          fi
          if [ "${PSI_MEMORY_ENABLED:-0}" = "1" ]; then
            PSI_MEMORY=$(fetch_psi_avg10 memory)
            DETAILS="$DETAILS MEM_PSI=${PSI_MEMORY}%"
          fi
          if [ "${PSI_IO_ENABLED:-0}" = "1" ]; then
            PSI_IO=$(fetch_psi_avg10 io)
            DETAILS="$DETAILS IO_PSI=${PSI_IO}%"
          fi
          if [ "${WEBSITE_ENABLED:-0}" = "1" ]; then
            website_index=1
            while [ "$website_index" -le "${WEBSITE_TARGET_COUNT:-0}" ]; do
              eval "WEBSITE_TARGET=\\${WEBSITE_TARGET_${website_index}:-}"
              if [ -n "${WEBSITE_TARGET:-}" ]; then
                if check_website "$WEBSITE_TARGET"; then
                  DETAILS="$DETAILS WEBSITE${website_index}=ok"
                else
                  DETAILS="$DETAILS WEBSITE${website_index}=down"
                fi
              fi
              website_index=$((website_index + 1))
            done
            if [ "${WEBSITE_TARGET_COUNT:-0}" = "0" ] && [ -n "${WEBSITE_URL:-}" ]; then
              if check_website "$WEBSITE_URL"; then
                DETAILS="$DETAILS WEBSITE=ok"
              else
                DETAILS="$DETAILS WEBSITE=down"
              fi
            fi
          fi
          TITLE="$(title_for_alert)"
          BODY="$SUMMARY$DETAILS"
          send_bark "$TITLE" "$BODY"
          exit $?
        fi

        CPU_STATE="normal"
        CPU_LAST_SENT=0
        MEMORY_STATE="normal"
        MEMORY_LAST_SENT=0
        PSI_CPU_STATE="normal"
        PSI_CPU_LAST_SENT=0
        PSI_MEMORY_STATE="normal"
        PSI_MEMORY_LAST_SENT=0
        PSI_IO_STATE="normal"
        PSI_IO_LAST_SENT=0
        if [ -r "$STATE_PATH" ]; then
          . "$STATE_PATH"
        fi

        [ -n "${COOLDOWN_SECONDS:-}" ] || COOLDOWN_SECONDS=600
        NOW=$(date +%s 2>/dev/null || busybox date +%s 2>/dev/null || echo 0)

        website_index=1
        while [ "$website_index" -le "${WEBSITE_TARGET_COUNT:-0}" ]; do
          eval ": \\${WEBSITE_${website_index}_STATE:=normal}"
          eval ": \\${WEBSITE_${website_index}_LAST_SENT:=0}"
          website_index=$((website_index + 1))
        done
        [ "${WEBSITE_TARGET_COUNT:-0}" = "0" ] && : "${WEBSITE_STATE:=normal}" "${WEBSITE_LAST_SENT:=0}"

        if [ "${CPU_USAGE_ENABLED:-0}" = "1" ]; then
          CPU_USAGE=$(fetch_cpu_usage)
          if [ "$CPU_USAGE" -ge "${CPU_USAGE_THRESHOLD:-90}" ]; then
            if should_send_again "${CPU_STATE:-normal}" "${CPU_LAST_SENT:-0}"; then
              if send_bark "$(title_for_alert)" "CPU 占用率 ${CPU_USAGE}% ，已超过阈值 ${CPU_USAGE_THRESHOLD}%"; then
                CPU_LAST_SENT="$NOW"
              fi
            fi
            CPU_STATE="alert"
          else
            CPU_STATE="normal"
          fi
        fi

        if [ "${MEMORY_USAGE_ENABLED:-0}" = "1" ]; then
          MEMORY_USAGE=$(fetch_memory_usage)
          if [ "$MEMORY_USAGE" -ge "${MEMORY_USAGE_THRESHOLD:-90}" ]; then
            if should_send_again "${MEMORY_STATE:-normal}" "${MEMORY_LAST_SENT:-0}"; then
              if send_bark "$(title_for_alert)" "内存占用率 ${MEMORY_USAGE}% ，已超过阈值 ${MEMORY_USAGE_THRESHOLD}%"; then
                MEMORY_LAST_SENT="$NOW"
              fi
            fi
            MEMORY_STATE="alert"
          else
            MEMORY_STATE="normal"
          fi
        fi

        if [ "${PSI_CPU_ENABLED:-0}" = "1" ]; then
          PSI_CPU=$(fetch_psi_avg10 cpu)
          if [ "$PSI_CPU" -ge "${PSI_CPU_THRESHOLD:-5}" ]; then
            if should_send_again "${PSI_CPU_STATE:-normal}" "${PSI_CPU_LAST_SENT:-0}"; then
              if send_bark "$(title_for_alert)" "CPU PSI(avg10) ${PSI_CPU}% ，已超过阈值 ${PSI_CPU_THRESHOLD}%"; then
                PSI_CPU_LAST_SENT="$NOW"
              fi
            fi
            PSI_CPU_STATE="alert"
          else
            PSI_CPU_STATE="normal"
          fi
        fi

        if [ "${PSI_MEMORY_ENABLED:-0}" = "1" ]; then
          PSI_MEMORY=$(fetch_psi_avg10 memory)
          if [ "$PSI_MEMORY" -ge "${PSI_MEMORY_THRESHOLD:-5}" ]; then
            if should_send_again "${PSI_MEMORY_STATE:-normal}" "${PSI_MEMORY_LAST_SENT:-0}"; then
              if send_bark "$(title_for_alert)" "内存 PSI(avg10) ${PSI_MEMORY}% ，已超过阈值 ${PSI_MEMORY_THRESHOLD}%"; then
                PSI_MEMORY_LAST_SENT="$NOW"
              fi
            fi
            PSI_MEMORY_STATE="alert"
          else
            PSI_MEMORY_STATE="normal"
          fi
        fi

        if [ "${PSI_IO_ENABLED:-0}" = "1" ]; then
          PSI_IO=$(fetch_psi_avg10 io)
          if [ "$PSI_IO" -ge "${PSI_IO_THRESHOLD:-5}" ]; then
            if should_send_again "${PSI_IO_STATE:-normal}" "${PSI_IO_LAST_SENT:-0}"; then
              if send_bark "$(title_for_alert)" "IO PSI(avg10) ${PSI_IO}% ，已超过阈值 ${PSI_IO_THRESHOLD}%"; then
                PSI_IO_LAST_SENT="$NOW"
              fi
            fi
            PSI_IO_STATE="alert"
          else
            PSI_IO_STATE="normal"
          fi
        fi

        if [ "${WEBSITE_ENABLED:-0}" = "1" ]; then
          website_index=1
          while [ "$website_index" -le "${WEBSITE_TARGET_COUNT:-0}" ]; do
            eval "WEBSITE_TARGET=\\${WEBSITE_TARGET_${website_index}:-}"
            if [ -n "${WEBSITE_TARGET:-}" ]; then
              eval "CURRENT_WEBSITE_STATE=\\${WEBSITE_${website_index}_STATE:-normal}"
              eval "CURRENT_WEBSITE_LAST_SENT=\\${WEBSITE_${website_index}_LAST_SENT:-0}"
              if check_website "$WEBSITE_TARGET"; then
                CURRENT_WEBSITE_STATE="normal"
              else
                if should_send_again "$CURRENT_WEBSITE_STATE" "$CURRENT_WEBSITE_LAST_SENT"; then
                  if send_bark "$(title_for_alert)" "网站连通性异常，${WEBSITE_TARGET} 无法访问"; then
                    CURRENT_WEBSITE_LAST_SENT="$NOW"
                  fi
                fi
                CURRENT_WEBSITE_STATE="alert"
              fi
              eval "WEBSITE_${website_index}_STATE=\\$CURRENT_WEBSITE_STATE"
              eval "WEBSITE_${website_index}_LAST_SENT=\\$CURRENT_WEBSITE_LAST_SENT"
            fi
            website_index=$((website_index + 1))
          done

          if [ "${WEBSITE_TARGET_COUNT:-0}" = "0" ] && [ -n "${WEBSITE_URL:-}" ]; then
            if check_website "$WEBSITE_URL"; then
              WEBSITE_STATE="normal"
            else
              if should_send_again "${WEBSITE_STATE:-normal}" "${WEBSITE_LAST_SENT:-0}"; then
                if send_bark "$(title_for_alert)" "网站连通性异常，${WEBSITE_URL} 无法访问"; then
                  WEBSITE_LAST_SENT="$NOW"
                fi
              fi
              WEBSITE_STATE="alert"
            fi
          fi
        fi

        WEBSITE_STATE_LINES=""
        website_index=1
        while [ "$website_index" -le "${WEBSITE_TARGET_COUNT:-0}" ]; do
          eval "CURRENT_WEBSITE_STATE=\\${WEBSITE_${website_index}_STATE:-normal}"
          eval "CURRENT_WEBSITE_LAST_SENT=\\${WEBSITE_${website_index}_LAST_SENT:-0}"
          WEBSITE_STATE_LINES="${WEBSITE_STATE_LINES}WEBSITE_${website_index}_STATE=${CURRENT_WEBSITE_STATE}\\nWEBSITE_${website_index}_LAST_SENT=${CURRENT_WEBSITE_LAST_SENT}\\n"
          website_index=$((website_index + 1))
        done

        printf 'CPU_STATE=%s\\nCPU_LAST_SENT=%s\\nMEMORY_STATE=%s\\nMEMORY_LAST_SENT=%s\\nPSI_CPU_STATE=%s\\nPSI_CPU_LAST_SENT=%s\\nPSI_MEMORY_STATE=%s\\nPSI_MEMORY_LAST_SENT=%s\\nPSI_IO_STATE=%s\\nPSI_IO_LAST_SENT=%s\\nWEBSITE_STATE=%s\\nWEBSITE_LAST_SENT=%s\\n%b' \
          "${CPU_STATE:-normal}" "${CPU_LAST_SENT:-0}" \
          "${MEMORY_STATE:-normal}" "${MEMORY_LAST_SENT:-0}" \
          "${PSI_CPU_STATE:-normal}" "${PSI_CPU_LAST_SENT:-0}" \
          "${PSI_MEMORY_STATE:-normal}" "${PSI_MEMORY_LAST_SENT:-0}" \
          "${PSI_IO_STATE:-normal}" "${PSI_IO_LAST_SENT:-0}" \
          "${WEBSITE_STATE:-normal}" "${WEBSITE_LAST_SENT:-0}" \
          "${WEBSITE_STATE_LINES:-}" > "$STATE_PATH"
        """
    }

    private static var remoteAlertTransportScript: String {
        """
        urlencode() {
          printf '%s' "$1" | od -An -tx1 | tr -d ' \\n' | sed 's/../%&/g'
        }

        send_bark() {
          title="$1"
          body="$2"
          base="${BARK_URL%/}"
          form_data="title=$(urlencode "$title")&body=$(urlencode "$body")&group=ios-monitor&isArchive=1"

          if command -v curl >/dev/null 2>&1; then
            curl -fsS -X POST "$base" \
              -H "Content-Type: application/x-www-form-urlencoded" \
              --data-urlencode "title=$title" \
              --data-urlencode "body=$body" \
              --data-urlencode "group=ios-monitor" \
              --data-urlencode "isArchive=1" >/dev/null 2>&1
            return $?
          fi
          if command -v wget >/dev/null 2>&1; then
            if wget --help 2>/dev/null | grep -q -- "--post-data"; then
              wget -qO- --header="Content-Type: application/x-www-form-urlencoded" \
                --post-data="$form_data" "$base" >/dev/null 2>&1
            else
              return 1
            fi
            return $?
          fi
          if command -v uclient-fetch >/dev/null 2>&1; then
            if uclient-fetch --help 2>/dev/null | grep -q -- "--post-data"; then
              uclient-fetch -q -O - --post-data="$form_data" "$base" >/dev/null 2>&1
            else
              return 1
            fi
            return $?
          fi
          return 1
        }
        """
    }

    private static var remoteAlertMemoryReaderScript: String {
        """
        fetch_memory_usage() {
          awk '
            /MemTotal:/ { total=$2 }
            /MemAvailable:/ { available=$2 }
            /MemFree:/ && available == 0 { available=$2 }
            END {
              if (total <= 0) {
                print 0
              } else {
                used = total - available
                if (used < 0) used = 0
                printf "%.0f\\n", (used * 100) / total
              }
            }
          ' /proc/meminfo 2>/dev/null || echo 0
        }
        """
    }

    private static var remoteAlertPSIReaderScript: String {
        """
        fetch_psi_avg10() {
          resource="$1"
          file="/proc/pressure/$resource"
          if [ ! -r "$file" ]; then
            echo 0
            return 0
          fi

          awk '
            function print_avg10(line, value) {
              value = line
              sub(/^.*avg10=/, "", value)
              sub(/ .*/, "", value)
              if (value == "") {
                print 0
              } else {
                printf "%.0f\\n", value + 0
              }
            }
            /^full / {
              print_avg10($0)
              found = 1
              exit
            }
            /^some / { some = $0 }
            END {
              if (!found && some != "") {
                print_avg10(some)
              } else if (!found) {
                print 0
              }
            }
          ' "$file" 2>/dev/null || echo 0
        }
        """
    }

    private static var remoteAlertWebsiteCheckerScript: String {
        """
        is_tcp_target() {
          target="$1"
          case "$target" in
            *://*) return 1 ;;
            \\[*\\]:[0-9]* ) return 0 ;;
            *:*)
              port="${target##*:}"
              host="${target%:*}"
              case "$port" in
                ''|*[!0-9]* ) return 1 ;;
              esac
              [ -n "$host" ]
              return $?
              ;;
            *)
              return 1
              ;;
          esac
        }

        tcp_target_host() {
          target="$1"
          case "$target" in
            \\[*\\]:* )
              value="${target%%]:*}"
              printf '%s' "${value#\\[}"
              ;;
            *:* )
              printf '%s' "${target%:*}"
              ;;
            * )
              printf '%s' "$target"
              ;;
          esac
        }

        tcp_target_port() {
          target="$1"
          case "$target" in
            \\[*\\]:* )
              printf '%s' "${target##*:}"
              ;;
            *:* )
              printf '%s' "${target##*:}"
              ;;
            * )
              printf '%s' ""
              ;;
          esac
        }

        check_tcp_target() {
          host="$1"
          port="$2"
          [ -n "$host" ] || return 1
          [ -n "$port" ] || return 1

          if command -v nc >/dev/null 2>&1; then
            nc -z -w 5 "$host" "$port" >/dev/null 2>&1
            return $?
          fi
          if command -v busybox >/dev/null 2>&1; then
            busybox nc -z -w 5 "$host" "$port" >/dev/null 2>&1
            return $?
          fi
          return 1
        }

        check_website() {
          target="$1"
          [ -n "$target" ] || return 1

          if is_tcp_target "$target"; then
            check_tcp_target "$(tcp_target_host "$target")" "$(tcp_target_port "$target")"
            return $?
          fi

          if command -v curl >/dev/null 2>&1; then
            curl -fsS -L --max-time 15 -o /dev/null "$target" >/dev/null 2>&1
            return $?
          fi
          if command -v wget >/dev/null 2>&1; then
            wget -q --spider --timeout=15 "$target" >/dev/null 2>&1
            return $?
          fi
          if command -v uclient-fetch >/dev/null 2>&1; then
            uclient-fetch -q -T 15 -O /dev/null "$target" >/dev/null 2>&1
            return $?
          fi
          return 1
        }
        """
    }

    private static var remoteAlertCPUReaderScript: String {
        """
        fetch_cpu_usage() {
          if [ ! -r /proc/stat ]; then
            echo "0"
            return
          fi

          cpu_sample() {
            awk '/^cpu / {idle=$5+$6; total=0; for (i=2; i<=NF; i++) total+=$i; printf "%.0f %.0f\\n", total, idle; found=1; exit} END {if (!found) print "0 0"}' /proc/stat 2>/dev/null
          }

          first=$(cpu_sample)
          sleep 1
          second=$(cpu_sample)

          awk -v first="$first" -v second="$second" 'BEGIN {
            split(first, a, " ")
            split(second, b, " ")
            totald = (b[1] + 0) - (a[1] + 0)
            idled = (b[2] + 0) - (a[2] + 0)
            if (totald <= 0) { print "0"; exit }
            usage = ((totald - idled) * 100) / totald
            if (usage < 0) usage = 0
            if (usage > 100) usage = 100
            printf "%.0f\\n", usage
          }'
        }
        """
    }

    private static func normalizedHostValue(from config: ServerConfig) -> String {
        let trimmed = config.host.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? config.name : trimmed
    }

    private static func shellBool(_ value: Bool) -> String {
        value ? "1" : "0"
    }

    private static func shellQuoted(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}
