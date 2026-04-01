import Foundation
import SwiftUI

struct ServerCard: View {
    let config: ServerConfig
    @ObservedObject var store: ServerStore
    var onOpenDetail: (() -> Void)? = nil
    @State private var showTerminal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: openDetail) {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    usageSummary
                    detailSummary
                }
            }
            .buttonStyle(.plain)

            HStack {
                Spacer()
                terminalButton
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 14, x: 0, y: 8)
        .fullScreenCover(isPresented: $showTerminal) {
            TerminalView(server: config)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(iconAccentColor.opacity(0.14))
                    .frame(width: 52, height: 52)

                Image(systemName: deviceIconName)
                    .font(.title3)
                    .foregroundColor(iconAccentColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(config.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(deviceSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }

                    Circle()
                        .fill(onlineIndicatorColor)
                        .frame(width: 10, height: 10)
                }

                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(uptimeText)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .opacity(stats == nil ? 0.8 : 1)

                if let temperatureText {
                    HStack(spacing: 5) {
                        Image(systemName: "thermometer")
                            .font(.caption2)
                        Text(temperatureText)
                            .font(.caption)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var usageSummary: some View {
        HStack(spacing: 22) {
            UsageRing(
                title: "CPU",
                value: stats?.isOnline == true ? stats?.cpuUsage : nil,
                color: .blue
            )

            UsageRing(
                title: "内存",
                value: stats?.isOnline == true ? stats?.memUsage : nil,
                color: .green
            )
        }
    }

    @ViewBuilder
    private var detailSummary: some View {
        if let stats {
            VStack(alignment: .leading, spacing: 8) {
                if stats.isOnline {
                    if stats.routerInfo.isRouter {
                        statPill(
                            icon: "dot.radiowaves.left.and.right",
                            text: "接入设备 \(stats.routerInfo.connectedDevices.count) 台"
                        )
                    }
                } else {
                    Text(stats.statusMessage.isEmpty ? "设备当前离线" : stats.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !stats.diagnostics.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(stats.diagnostics.prefix(2), id: \.self) { item in
                            Text(item)
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.orange)
                }
            }
        } else {
            Text("正在获取设备状态…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var terminalButton: some View {
        Button(action: { showTerminal = true }) {
            Image(systemName: "terminal")
                .font(.subheadline)
                .foregroundColor(terminalButtonForeground)
                .frame(width: 34, height: 34)
                .background(terminalButtonBackground)
                .clipShape(Circle())
        }
        .disabled(stats?.isOnline != true || isRefreshing)
        .opacity(stats?.isOnline == true && !isRefreshing ? 1 : 0.55)
    }

    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func openDetail() {
        onOpenDetail?()
    }

    private var stats: ServerStats? {
        store.stats(for: config)
    }

    private var isRefreshing: Bool {
        store.isRefreshing(config.id)
    }

    private var uptimeText: String {
        guard let stats, !stats.uptime.isEmpty else {
            return "等待运行时长"
        }
        return stats.uptime
    }

    private var deviceSubtitle: String {
        guard let stats else {
            return config.host
        }

        if stats.routerInfo.isRouter {
            return "路由器"
        }

        if !stats.hostname.isEmpty {
            return stats.hostname
        }

        if !stats.osName.isEmpty {
            return stats.osName
        }

        return config.host
    }

    private var deviceIconName: String {
        guard let stats else {
            return "server.rack"
        }

        if stats.routerInfo.isRouter {
            return "wifi.router"
        }

        let fingerprint = "\(stats.osName) \(stats.hostname) \(stats.cpuModel)".lowercased()
        if fingerprint.contains("raspberry") {
            return "cpu"
        }
        if fingerprint.contains("mac") {
            return "desktopcomputer"
        }
        return "server.rack"
    }

    private var iconAccentColor: Color {
        stats?.routerInfo.isRouter == true ? .orange : .blue
    }

    private var onlineIndicatorColor: Color {
        if isRefreshing {
            return .orange
        }
        guard let stats else {
            return .gray
        }
        return stats.isOnline ? .green : .red
    }

    private var temperatureText: String? {
        guard let stats, stats.isOnline, let temperature = stats.cpuTemperatureC else {
            return nil
        }
        return String(format: "%.0f°C", temperature)
    }

    private var terminalButtonBackground: Color {
        stats?.isOnline == true && !isRefreshing
            ? Color(.secondarySystemBackground)
            : Color(.systemGray5)
    }

    private var terminalButtonForeground: Color {
        .secondary
    }

    private var cardBackgroundColor: Color {
        Color(.systemBackground)
    }

    private var cardBorderColor: Color {
        Color.primary.opacity(0.08)
    }

    private var shadowColor: Color {
        Color.black.opacity(0.12)
    }
}
