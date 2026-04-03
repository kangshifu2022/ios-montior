import SwiftUI

struct AddServerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: ServerStore
    
    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword = false
    
    var isEditing: Bool = false
    var editingServer: ServerConfig? = nil
    
    init(store: ServerStore, editingServer: ServerConfig? = nil) {
        self.store = store
        self.editingServer = editingServer
        self.isEditing = editingServer != nil
        if let s = editingServer {
            _name = State(initialValue: s.name)
            _host = State(initialValue: s.host)
            _port = State(initialValue: String(s.port))
            _username = State(initialValue: s.username)
            _password = State(initialValue: s.password)
        }
    }
    
    var canSave: Bool {
        !host.isEmpty && !username.isEmpty && !password.isEmpty
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    HStack {
                        Text("名称")
                        Spacer()
                        TextField("默认使用主机名", text: $name)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("主机")
                        Spacer()
                        TextField("IP 地址或域名", text: $host)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                    }
                    HStack {
                        Text("端口")
                        Spacer()
                        TextField("22", text: $port)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .keyboardType(.numberPad)
                    }
                }
                
                Section(header: Text("认证方式")) {
                    HStack {
                        Text("用户名")
                        Spacer()
                        TextField("root", text: $username)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .autocapitalization(.none)
                    }
                    HStack {
                        Text("密码")
                        Spacer()
                        if showPassword {
                            TextField("密码", text: $password)
                                .multilineTextAlignment(.trailing)
                                .foregroundColor(.secondary)
                                .autocapitalization(.none)
                        } else {
                            SecureField("密码", text: $password)
                                .multilineTextAlignment(.trailing)
                        }
                        Button(action: { showPassword.toggle() }) {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑服务器" : "添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let config = ServerConfig(
                            id: editingServer?.id ?? UUID(),
                            name: name.isEmpty ? host : name,
                            host: host,
                            port: Int(port) ?? 22,
                            username: username,
                            password: password,
                            barkURL: editingServer?.barkURL ?? "",
                            cpuAlertEnabled: editingServer?.cpuAlertEnabled ?? false,
                            cpuAlertThreshold: editingServer?.cpuAlertThreshold ?? 90,
                            cpuAlertCooldownMinutes: editingServer?.cpuAlertCooldownMinutes ?? 10,
                            barkTestTitleTemplate: editingServer?.barkTestTitleTemplate ?? ServerConfig.defaultBarkTestTitleTemplate,
                            barkTestBodyTemplate: editingServer?.barkTestBodyTemplate ?? ServerConfig.defaultBarkTestBodyTemplate,
                            barkAlertTitleTemplate: editingServer?.barkAlertTitleTemplate ?? ServerConfig.defaultBarkAlertTitleTemplate,
                            barkAlertBodyTemplate: editingServer?.barkAlertBodyTemplate ?? ServerConfig.defaultBarkAlertBodyTemplate
                        )
                        if isEditing {
                            store.update(config)
                        } else {
                            store.add(config)
                        }
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
