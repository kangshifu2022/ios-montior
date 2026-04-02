import SwiftUI

struct SystemHealthBadge: View {
    let stats: ServerStats?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let assessment = SystemHealthAssessment(stats: stats)

        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(trackColor, lineWidth: 4)

                Circle()
                    .trim(from: 0, to: assessment.healthScore)
                    .stroke(
                        assessment.color.gradient,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: assessment.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(assessment.color)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(assessment.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(assessment.color)
                    .lineLimit(1)

                Text(assessment.reason)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(minHeight: 34, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: assessment.healthScore)
    }

    private var trackColor: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.10)
        case .light:
            return Color.black.opacity(0.08)
        @unknown default:
            return Color.black.opacity(0.08)
        }
    }
}

private struct SystemHealthAssessment {
    let healthScore: CGFloat
    let title: String
    let reason: String
    let color: Color
    let iconName: String

    init(stats: ServerStats?) {
        guard let stats else {
            healthScore = 0.25
            title = "分析中"
            reason = "等待系统数据"
            color = .gray
            iconName = "hourglass"
            return
        }

        guard stats.isOnline else {
            healthScore = 0.15
            title = "离线"
            reason = "暂时无法评估健康度"
            color = .gray
            iconName = "bolt.slash"
            return
        }

        let psi = stats.pressure
        let cpuPressure = normalizedCPUPressure(from: psi)
        let memoryPressure = normalizedMemoryPressure(from: psi)
        let ioPressure = normalizedIOPressure(from: psi)
        let loadPressure = normalizedLoadPressure(from: stats)
        let hasPSI = psi.cpuSomeAvg10 != nil ||
            psi.memorySomeAvg10 != nil ||
            psi.memoryFullAvg10 != nil ||
            psi.ioSomeAvg10 != nil ||
            psi.ioFullAvg10 != nil

        let dominantPressure = max(cpuPressure, memoryPressure, ioPressure)
        let blendedPSI = max(dominantPressure, (cpuPressure + memoryPressure + ioPressure) / 3.0)
        let overallPressure = hasPSI
            ? max(blendedPSI, loadPressure * 0.55)
            : max(loadPressure, stats.cpuUsage * 0.75, stats.memUsage * 0.60)

        healthScore = CGFloat(max(0.08, 1.0 - min(overallPressure, 1.0)))

        switch overallPressure {
        case ..<0.25:
            title = "健康"
            color = Color(red: 0.18, green: 0.72, blue: 0.42)
            iconName = "checkmark"
        case ..<0.5:
            title = "轻微压力"
            color = Color(red: 0.93, green: 0.72, blue: 0.18)
            iconName = "gauge.open.with.lines.needle.33percent"
        case ..<0.75:
            title = "压力较大"
            color = Color(red: 0.95, green: 0.50, blue: 0.20)
            iconName = "exclamationmark"
        default:
            title = "严重拥塞"
            color = Color(red: 0.90, green: 0.24, blue: 0.22)
            iconName = "flame"
        }

        reason = Self.reasonText(
            stats: stats,
            hasPSI: hasPSI,
            cpuPressure: cpuPressure,
            memoryPressure: memoryPressure,
            ioPressure: ioPressure,
            loadPressure: loadPressure
        )
    }

    private static func normalizedCPUPressure(from psi: PressureMetrics) -> Double {
        min((psi.cpuSomeAvg10 ?? 0) / 25.0, 1.0)
    }

    private static func normalizedMemoryPressure(from psi: PressureMetrics) -> Double {
        let some = min((psi.memorySomeAvg10 ?? 0) / 20.0, 1.0)
        let full = min((psi.memoryFullAvg10 ?? 0) / 5.0, 1.0)
        return max(some * 0.75, full)
    }

    private static func normalizedIOPressure(from psi: PressureMetrics) -> Double {
        let some = min((psi.ioSomeAvg10 ?? 0) / 20.0, 1.0)
        let full = min((psi.ioFullAvg10 ?? 0) / 5.0, 1.0)
        return max(some * 0.75, full)
    }

    private static func normalizedLoadPressure(from stats: ServerStats) -> Double {
        guard let load = stats.loadAverage1m else { return 0 }
        let cores = max(stats.cpuCores, 1)
        return min((load / Double(cores)) / 1.5, 1.0)
    }

    private static func reasonText(
        stats: ServerStats,
        hasPSI: Bool,
        cpuPressure: Double,
        memoryPressure: Double,
        ioPressure: Double,
        loadPressure: Double
    ) -> String {
        if hasPSI {
            if memoryPressure >= ioPressure && memoryPressure >= cpuPressure && memoryPressure >= 0.45 {
                if let full = stats.pressure.memoryFullAvg10, full >= 1 {
                    return "内存阻塞明显"
                }
                return "内存压力升高"
            }

            if ioPressure >= memoryPressure && ioPressure >= cpuPressure && ioPressure >= 0.45 {
                if let full = stats.pressure.ioFullAvg10, full >= 1 {
                    return "磁盘 IO 堵塞明显"
                }
                return "IO 等待偏高"
            }

            if cpuPressure >= 0.45 {
                return "CPU 等待升高"
            }

            if loadPressure >= 0.55 {
                return "负载接近核心上限"
            }

            return "资源压力整体平稳"
        }

        if loadPressure >= 0.55 {
            return "PSI 不可用，按负载估算"
        }

        if stats.cpuUsage >= 0.75 {
            return "CPU 使用率偏高"
        }

        if stats.memUsage >= 0.80 {
            return "内存使用率偏高"
        }

        return "按负载估算整体平稳"
    }
}
