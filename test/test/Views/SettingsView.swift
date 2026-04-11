import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ServerStore
    @EnvironmentObject private var terminalWorkspace: TerminalWorkspace
    @AppStorage(ExperimentalHomeTheme.storageKey) private var experimentalHomeThemeRawValue = ExperimentalHomeTheme.system.rawValue
    @AppStorage(TerminalDefaultConnectionMode.storageKey) private var terminalDefaultConnectionModeRawValue = TerminalDefaultConnectionMode.directSSH.rawValue
    @AppStorage(TerminalRestorePolicy.storageKey) private var terminalRestorePolicyRawValue = TerminalRestorePolicy.alwaysStartNew.rawValue
    @State private var showAddServer = false
    @State private var editingServer: ServerConfig? = nil
    
    var body: some View {
        NavigationView {
            List {
                serverManagementSection

                Section(header: Text("终端")) {
                    Picker("默认连接模式", selection: $terminalDefaultConnectionModeRawValue) {
                        ForEach(TerminalDefaultConnectionMode.allCases) { mode in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                Text(mode.subtitle)
                            }
                            .tag(mode.rawValue)
                        }
                    }

                    Text(selectedTerminalDefaultConnectionMode.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Picker("恢复策略", selection: $terminalRestorePolicyRawValue) {
                        ForEach(TerminalRestorePolicy.allCases) { policy in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(policy.title)
                                Text(policy.subtitle)
                            }
                            .tag(policy.rawValue)
                        }
                    }

                    Text(selectedTerminalRestorePolicy.subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Text("持久 tmux 模式会在本地记住最近的远端会话和输出预览，适合长时间任务和意外恢复。")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    NavigationLink("终端诊断日志") {
                        TerminalDiagnosticsView()
                    }

                    NavigationLink("监控诊断日志") {
                        ServerMonitorDiagnosticsView()
                    }
                }

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
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddServer = true }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("添加服务器")
                }
            }
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

    private var serverManagementSection: some View {
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
                    Button(action: { duplicateServer(server) }) {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制\(server.name)")

                    Button(action: { editingServer = server }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑\(server.name)")
                }
                .padding(.vertical, 4)
            }
            .onDelete(perform: deleteServers)
        }
    }

    private var selectedTerminalDefaultConnectionMode: TerminalDefaultConnectionMode {
        TerminalDefaultConnectionMode(rawValue: terminalDefaultConnectionModeRawValue) ?? .directSSH
    }

    private var selectedTerminalRestorePolicy: TerminalRestorePolicy {
        TerminalRestorePolicy(rawValue: terminalRestorePolicyRawValue) ?? .alwaysStartNew
    }

    private func deleteServers(at offsets: IndexSet) {
        let deletedIDs = offsets.map { store.servers[$0].id }
        for id in deletedIDs {
            terminalWorkspace.closeSessions(forServerID: id)
            TerminalPersistenceStore.removeSessions(for: id)
        }
        store.delete(at: offsets)
    }

    private func duplicateServer(_ server: ServerConfig) {
        let duplicatedServer = ServerConfig(
            name: "\(server.name) 副本",
            groupName: server.groupName,
            host: server.host,
            port: server.port,
            username: server.username,
            password: server.password,
            barkURL: server.barkURL,
            alertConfiguration: server.alertConfiguration
        )
        store.add(duplicatedServer)
    }
}
