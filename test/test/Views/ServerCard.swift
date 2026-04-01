import Foundation
import SwiftUI
import UIKit

struct ServerCard: View {
    let config: ServerConfig
    @ObservedObject var store: ServerStore
    var onOpenDetail: (() -> Void)? = nil
    @State private var showTerminal = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            usageSummary
                .frame(width: 132, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                header
                detailSummary
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openDetail)
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
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(iconAccentColor.opacity(0.14))
                    .frame(width: 42, height: 42)

                Image(systemName: deviceIconName)
                    .font(.subheadline)
                    .foregroundColor(iconAccentColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(config.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(deviceSubtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.75)
                }

                Circle()
                    .fill(onlineIndicatorColor)
                    .frame(width: 9, height: 9)

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text(uptimeText)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundColor(.secondary)

                terminalButton
            }
        }
    }

    private var usageSummary: some View {
        HStack(spacing: 10) {
            UsageRing(
                title: "CPU",
                value: stats?.isOnline == true ? stats?.cpuUsage : nil,
                color: .green
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
            if stats.isOnline {
                if temperatureText != nil || wifi24TemperatureText != nil || wifi5TemperatureText != nil {
                    HStack(spacing: 8) {
                        if let temperatureText {
                            temperaturePill(label: "CPU", value: temperatureText)
                        }

                        if let wifi24TemperatureText {
                            temperaturePill(label: "2.4G", value: wifi24TemperatureText)
                        }

                        if let wifi5TemperatureText {
                            temperaturePill(label: "5G", value: wifi5TemperatureText)
                        }

                        Spacer(minLength: 0)
                    }
                }
            } else {
                Text(stats.statusMessage.isEmpty ? "设备当前离线" : stats.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        } else {
            Text("正在获取设备状态…")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var terminalButton: some View {
        Button(action: { showTerminal = true }) {
            Image(systemName: "terminal")
                .font(.caption)
                .foregroundColor(terminalButtonForeground)
                .frame(width: 26, height: 26)
                .background(terminalButtonBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(stats?.isOnline != true || isRefreshing)
        .opacity(stats?.isOnline == true && !isRefreshing ? 1 : 0.45)
    }

    private func temperaturePill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "thermometer")
                .font(.caption2)
            Text(label)
                .font(.caption2)
            Text(value)
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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
            return "--"
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
        return temperatureValueText(temperature)
    }

    private var wifi24TemperatureText: String? {
        guard let stats, stats.isOnline, let temperature = stats.wifi24TemperatureC else {
            return nil
        }
        return temperatureValueText(temperature)
    }

    private var wifi5TemperatureText: String? {
        guard let stats, stats.isOnline, let temperature = stats.wifi5TemperatureC else {
            return nil
        }
        return temperatureValueText(temperature)
    }

    private func temperatureValueText(_ temperature: Double) -> String {
        String(format: "%.0f°C", temperature)
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
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1)
            }
            return .systemBackground
        })
    }

    private var cardBorderColor: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor.white.withAlphaComponent(0.08)
            }
            return UIColor.black.withAlphaComponent(0.06)
        })
    }

    private var shadowColor: Color {
        Color.black.opacity(0.16)
    }
}
