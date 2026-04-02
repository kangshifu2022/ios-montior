import SwiftUI
import UniformTypeIdentifiers

struct DevicesView: View {
    @ObservedObject var store: ServerStore
    @State private var selectedServer: ServerConfig?
    @State private var draggedServer: ServerConfig?

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
                                .scaleEffect(draggedServer?.id == config.id ? 0.98 : 1)
                                .opacity(draggedServer?.id == config.id ? 0.82 : 1)
                                .animation(.easeInOut(duration: 0.18), value: draggedServer?.id == config.id)
                                .onDrag {
                                    draggedServer = config
                                    return NSItemProvider(object: config.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: DeviceCardDropDelegate(
                                        current: config,
                                        draggedServer: $draggedServer,
                                        store: store
                                    )
                                )
                            }
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: DeviceListDropDelegate(draggedServer: $draggedServer)
                        )
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

private struct DeviceCardDropDelegate: DropDelegate {
    let current: ServerConfig
    @Binding var draggedServer: ServerConfig?
    let store: ServerStore

    func dropEntered(info: DropInfo) {
        guard let draggedServer, draggedServer.id != current.id else {
            return
        }

        guard let fromIndex = store.servers.firstIndex(where: { $0.id == draggedServer.id }),
              let toIndex = store.servers.firstIndex(where: { $0.id == current.id }) else {
            return
        }

        if store.servers[toIndex].id != draggedServer.id {
            let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
            store.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedServer = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}

private struct DeviceListDropDelegate: DropDelegate {
    @Binding var draggedServer: ServerConfig?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedServer = nil
        return true
    }
}
