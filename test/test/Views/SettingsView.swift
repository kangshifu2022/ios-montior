import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ServerStore
    @AppStorage(ExperimentalHomeTheme.storageKey) private var experimentalHomeThemeRawValue = ExperimentalHomeTheme.system.rawValue
    @State private var showAddServer = false
    @State private var editingServer: ServerConfig? = nil
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("界面实验")) {
                    Text("首屏已经统一切到实验版，后续首页样式都只在这一套上继续迭代。")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Picker("试验版主题", selection: $experimentalHomeThemeRawValue) {
                        ForEach(ExperimentalHomeTheme.allCases) { theme in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.title)
                                Text(theme.subtitle)
                            }
                            .tag(theme.rawValue)
                        }
                    }

                    Text(selectedExperimentalHomeTheme.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

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

    private var selectedExperimentalHomeTheme: ExperimentalHomeTheme {
        ExperimentalHomeTheme(rawValue: experimentalHomeThemeRawValue) ?? .system
    }
}
