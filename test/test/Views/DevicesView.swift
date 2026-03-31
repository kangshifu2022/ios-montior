import SwiftUI

struct DevicesView: View {
    @ObservedObject var store: ServerStore

    var body: some View {
        NavigationView {
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
                        VStack(spacing: 12) {
                            ForEach(store.servers) { config in
                                ServerCard(config: config)
                                    .padding(.horizontal, 16)
                            }
                        }
                        .padding(.vertical, 20)
                    }
                }
            }
            .navigationTitle("概览")
        }
    }
}
