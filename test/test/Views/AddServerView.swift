import SwiftUI

struct AddServerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var store: ServerStore
    @FocusState private var isGroupNameFieldFocused: Bool
    
    @State private var name: String = ""
    @State private var groupName: String = ""
    @State private var host: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var showPassword = false
    @State private var showsDeleteConfirmation = false
    
    var isEditing: Bool = false
    var editingServer: ServerConfig? = nil
    
    init(store: ServerStore, editingServer: ServerConfig? = nil) {
        self.store = store
        self.editingServer = editingServer
        self.isEditing = editingServer != nil
        if let s = editingServer {
            _name = State(initialValue: s.name)
            _groupName = State(initialValue: Self.editableGroupName(from: s.resolvedGroupName))
            _host = State(initialValue: s.host)
            _port = State(initialValue: String(s.port))
            _username = State(initialValue: s.username)
            _password = State(initialValue: s.password)
        }
    }
    
    var canSave: Bool {
        !host.isEmpty && !username.isEmpty && !password.isEmpty
    }

    private var availableGroupNames: [String] {
        var groups = [ServerConfig.allGroupName]
        var seenGroups = Set(groups)

        for server in store.servers {
            let group = server.resolvedGroupName
            if seenGroups.insert(group).inserted {
                groups.append(group)
            }
        }

        return groups
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
                        Text("分组")
                        Spacer()
                        TextField(isGroupNameFieldFocused ? "" : ServerConfig.allGroupName, text: $groupName)
                            .multilineTextAlignment(.trailing)
                            .foregroundColor(.secondary)
                            .focused($isGroupNameFieldFocused)
                            .onChange(of: isGroupNameFieldFocused) { _, isFocused in
                                guard isFocused else { return }
                                guard ServerConfig.normalizedGroupName(groupName) == ServerConfig.allGroupName else { return }
                                groupName = ""
                            }
                    }

                    if !availableGroupNames.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("已有分组")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableGroupNames, id: \.self) { existingGroupName in
                                        let isSelected = ServerConfig.normalizedGroupName(groupName) == existingGroupName

                                        Button {
                                            groupName = Self.editableGroupName(from: existingGroupName)
                                        } label: {
                                            Text(existingGroupName)
                                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                                .foregroundColor(isSelected ? .white : .primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 7)
                                                .background(
                                                    Capsule()
                                                        .fill(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
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

                if isEditing {
                    Section {
                        Button("删除设备", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                    } footer: {
                        Text("删除后会移除这台设备的配置和缓存数据。")
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑服务器" : "添加服务器")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "删除设备",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    handleDelete()
                }

                Button("取消", role: .cancel) {}
            } message: {
                Text("确认删除这台设备？")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let config = ServerConfig(
                            id: editingServer?.id ?? UUID(),
                            name: name.isEmpty ? host : name,
                            groupName: ServerConfig.normalizedGroupName(groupName),
                            host: host,
                            port: Int(port) ?? 22,
                            username: username,
                            password: password,
                            barkURL: editingServer?.barkURL ?? "",
                            alertConfiguration: editingServer?.alertConfiguration ?? AlertConfiguration()
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

    private func handleDelete() {
        guard let id = editingServer?.id else {
            return
        }

        store.deleteServer(id: id)
        dismiss()
    }

    private static func editableGroupName(from value: String) -> String {
        ServerConfig.normalizedGroupName(value) == ServerConfig.allGroupName ? "" : value
    }
}
