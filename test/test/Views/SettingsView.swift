import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ServerStore
    @State private var showAddServer = false
    @State private var editingServer: ServerConfig? = nil
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("服务器管理")) {
                    ForEach(store.servers) { server in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name)
                                    .font(.headline)
                                Text("\(server.username)@\(server.host):\(server.port)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(action: { editingServer = server }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { store.delete(at: $0) }
                    
                    Button(action: { showAddServer = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                            Text("添加服务器")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showAddServer) {
                AddServerView(store: store)
            }
            .sheet(item: $editingServer) { server in
                AddServerView(store: store, editingServer: server)
            }
        }
    }
}
