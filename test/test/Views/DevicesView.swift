import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: ServerStore
    @State private var selectedServer: ServerConfig?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.servers.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("还没有服务器")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("前往设置页面添加服务器")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    } else {
                        VStack(spacing: 16) {
                            ForEach(store.servers) { config in
                                ServerCard(config: config, store: store) {
                                    selectedServer = config
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await store.refreshAllIfNeeded(forceDynamic: true, forceStatic: true)
            }
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
}
