import Foundation
import SwiftUI
import UIKit

struct ServerCard: View {
    let config: ServerConfig
    @ObservedObject var store: ServerStore
    var onOpenDetail: (() -> Void)? = nil
    @State private var showTerminal = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            usageSummary
            Spacer(minLength: 0)
            detailSummary
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: openDetail)
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(cardBorderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            terminalButton
                .padding(.top, 18)
                .padding(.trailing, 18)
        }
        .shadow(color: shadowColor, radius: 14, x: 0, y: 8)
        .fullScreenCover(isPresented: $showTerminal) {
            TerminalView(server: config)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
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
                    Text(config.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text(osDisplayText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text(uptimeText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Circle()
                    .fill(onlineIndicatorColor)
                    .frame(width: 9, height: 9)
            }
        }
    }

    private var usageSummary: some View {
        HStack(alignment: .top, spacing: 14) {
            ringsSummary
            metricsSummary
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailSummary: some View {
        if let stats {
            if !stats.isOnline {
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
        }
        .buttonStyle(.plain)
        .disabled(stats?.isOnline != true)
        .opacity(stats?.isOnline == true ? 1 : 0.45)
    }

    private var ringsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
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

            if stats?.isOnline == true, !temperatureItems.isEmpty {
                HStack(spacing: 6) {
                    ForEach(temperatureItems) { item in
                        temperatureBadge(item)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var metricsSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            metricRow(
                icon: "arrow.down.circle",
                label: "下载",
                value: downloadSpeedText
            )

            metricRow(
                icon: "arrow.up.circle",
                label: "上传",
                value: uploadSpeedText
            )

            metricRow(
                icon: "speedometer",
                label: "Load",
                value: loadAverageText
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 14)

            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func temperatureBadge(_ item: TemperatureItem) -> some View {
        HStack(spacing: 4) {
            Text(item.label)
                .font(.caption2)
            Text(item.value)
                .font(.caption2)
                .monospacedDigit()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(cardSecondaryFill)
        .clipShape(Capsule())
    }

    private func openDetail() {
        onOpenDetail?()
    }

    private var stats: ServerStats? {
        store.stats(for: config)
    }

    private var uptimeText: String {
        guard let stats, !stats.uptime.isEmpty else {
            return "--"
        }
        return stats.uptime
    }

    private var osDisplayText: String {
        guard let stats else {
            return "Unknown OS"
        }

        let osName = stats.osName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !osName.isEmpty else {
            return stats.routerInfo.isRouter ? "Router OS" : "Unknown OS"
        }

        let lowercased = osName.lowercased()

        if lowercased.contains("openwrt") {
            return "OpenWrt"
        }
        if lowercased.contains("ubuntu") {
            return "Ubuntu"
        }
        if lowercased.contains("debian") {
            return "Debian"
        }
        if lowercased.contains("centos") {
            return "CentOS"
        }
        if lowercased.contains("fedora") {
            return "Fedora"
        }
        if lowercased.contains("arch") {
            return "Arch Linux"
        }
        if lowercased.contains("macos") || lowercased.contains("darwin") {
            return "macOS"
        }
        if lowercased.contains("raspbian") {
            return "Raspbian"
        }
        if lowercased.contains("linux") {
            return "Linux"
        }

        return osName
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
        guard let stats else {
            return .gray
        }
        return stats.isOnline ? .green : .red
    }

    private var downloadSpeedText: String {
        guard let stats, stats.isOnline else {
            return "--"
        }
        return stats.downloadSpeed
    }

    private var uploadSpeedText: String {
        guard let stats, stats.isOnline else {
            return "--"
        }
        return stats.uploadSpeed
    }

    private var loadAverageText: String {
        guard let stats, stats.isOnline else {
            return "--"
        }
        if let load = stats.loadAverage1m {
            return String(format: "%.2f", load)
        }
        return "--"
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

    private var temperatureItems: [TemperatureItem] {
        var items: [TemperatureItem] = []

        if let temperatureText {
            items.append(.init(label: "CPU", value: temperatureText))
        }

        if let wifi24TemperatureText {
            items.append(.init(label: "2.4G", value: wifi24TemperatureText))
        }

        if let wifi5TemperatureText {
            items.append(.init(label: "5G", value: wifi5TemperatureText))
        }

        return items
    }

    private var terminalButtonForeground: Color {
        .secondary
    }

    private var cardBackgroundColor: Color {
        Color(uiColor: UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .dark {
                return UIColor(red: 25.0 / 255.0, green: 26.0 / 255.0, blue: 27.0 / 255.0, alpha: 1)
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

    private var cardSecondaryFill: Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0.23, green: 0.24, blue: 0.26)
        case .light:
            return Color(.secondarySystemBackground)
        @unknown default:
            return Color(.secondarySystemBackground)
        }
    }
}

private struct TemperatureItem: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}
