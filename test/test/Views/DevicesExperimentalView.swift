import SwiftUI

struct DevicesExperimentalView: View {
    @ObservedObject var store: ServerStore
    @AppStorage(HomeScreenStyle.storageKey) private var homeScreenStyleRawValue = HomeScreenStyle.experimental.rawValue
    @State private var selectedServer: ServerConfig?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    experimentBanner
                    experimentSummary
                    experimentList
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("概览")
            .task(id: store.servers.map(\.id)) {
                await store.refreshAllIfNeeded()

                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await store.refreshAllIfNeeded(forceDynamic: true)
                }
            }
            .navigationDestination(item: $selectedServer) { config in
                DeviceDetailView(config: config, store: store)
            }
        }
    }

    private var experimentBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("首屏实验版")
                .font(.title2.weight(.bold))
            Text("这是一块安全的实验区。我们后面改新首屏时，只会动这里，经典版布局会一直保留。")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("切回经典版") {
                homeScreenStyleRawValue = HomeScreenStyle.classic.rawValue
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color.orange.opacity(0.16), Color.yellow.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var experimentSummary: some View {
        HStack(spacing: 12) {
            experimentMetricCard(
                title: "服务器",
                value: "\(store.servers.count)",
                subtitle: "已接入"
            )
            experimentMetricCard(
                title: "在线状态",
                value: "\(onlineCount)",
                subtitle: "最近刷新在线"
            )
        }
    }

    private var experimentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("实验版临时列表")
                .font(.headline)

            if store.servers.isEmpty {
                Text("当前还没有服务器，后续我们可以直接围绕这个空状态重新设计。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(store.servers) { server in
                    Button {
                        selectedServer = server
                    } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Circle()
                                .fill(statusColor(for: server))
                                .frame(width: 10, height: 10)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                Text("\(server.username)@\(server.host):\(server.port)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var onlineCount: Int {
        store.servers.reduce(into: 0) { count, server in
            if store.stats(for: server)?.isOnline == true {
                count += 1
            }
        }
    }

    private func statusColor(for server: ServerConfig) -> Color {
        store.stats(for: server)?.isOnline == true ? .green : .orange
    }

    private func experimentMetricCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
