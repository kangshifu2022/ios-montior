import SwiftUI

struct AlertsView: View {
    @ObservedObject var store: ServerStore
    @Environment(\.openURL) private var openURL

    @State private var selectedServerID: UUID?
    @State private var barkURL: String = ""
    @State private var cpuThreshold: Int = 90
    @State private var cooldownMinutes: Int = 10
    @State private var showInstallConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var showBarkHelp = false

    private let barkAppStoreURL = URL(string: "https://apps.apple.com/app/id1403753865")!

    private var selectedServer: ServerConfig? {
        if let selectedServerID,
           let server = store.servers.first(where: { $0.id == selectedServerID }) {
            return server
        }
        return store.servers.first
    }

    private var selectedStatus: RemoteAlertStatus? {
        guard let selectedServer else { return nil }
        return store.remoteAlertStatus(for: selectedServer)
    }

    private var isBusy: Bool {
        guard let selectedServer else { return false }
        return store.isPerformingRemoteAlertAction(selectedServer.id)
    }

    private var hasUnsavedChanges: Bool {
        guard let selectedServer else { return false }
        return barkURL.trimmingCharacters(in: .whitespacesAndNewlines) != selectedServer.barkURL ||
            cpuThreshold != selectedServer.cpuAlertThreshold ||
            cooldownMinutes != selectedServer.cpuAlertCooldownMinutes
    }

    private var barkURLIsFilled: Bool {
        !barkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.servers.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            serverPickerCard
                            warningCard
                            barkSetupCard
                            configurationCard
                            statusCard
                            actionsCard
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("告警")
            .task(id: selectedServer?.id) {
                syncSelection()
                guard let selectedServer else { return }
                loadForm(from: selectedServer)
                await store.refreshRemoteAlertStatus(for: selectedServer)
            }
            .onAppear {
                syncSelection()
                if let selectedServer {
                    loadForm(from: selectedServer)
                }
            }
            .onChange(of: store.servers.map(\.id)) { _, _ in
                syncSelection()
                if let selectedServer {
                    loadForm(from: selectedServer)
                }
            }
            .onChange(of: selectedServerID) { _, _ in
                if let selectedServer {
                    loadForm(from: selectedServer)
                }
            }
            .alert("安装并启用远端告警", isPresented: $showInstallConfirmation) {
                Button("取消", role: .cancel) {}
                Button("安装并启用") {
                    Task { await installRemoteAlert() }
                }
            } message: {
                Text("将向目标服务器写入常驻脚本和 cron 定时任务，以实现 7x24 小时 CPU 告警。Bark 推送地址会保存到目标服务器，请仅在你信任的服务器上启用。")
            }
            .alert("卸载远端告警", isPresented: $showRemoveConfirmation) {
                Button("取消", role: .cancel) {}
                Button("卸载", role: .destructive) {
                    Task { await removeRemoteAlert() }
                }
            } message: {
                Text("将尝试删除目标服务器上的告警脚本、配置文件和 cron 任务。若远端环境被手工修改，可能仍需你自行检查残留。")
            }
            .sheet(isPresented: $showBarkHelp) {
                BarkHelpView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("还没有可配置的服务器")
                .font(.headline)
            Text("请先前往设置页面添加服务器，再为它配置 Bark 远端告警。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }

    private var serverPickerCard: some View {
        AlertSectionCard(title: "目标服务器", icon: "server.rack") {
            Picker("目标服务器", selection: Binding(
                get: { selectedServerID ?? store.servers.first?.id ?? UUID() },
                set: { selectedServerID = $0 }
            )) {
                ForEach(store.servers) { server in
                    Text(server.name).tag(server.id)
                }
            }
            .pickerStyle(.menu)

            if let selectedServer {
                Text("\(selectedServer.username)@\(selectedServer.host):\(selectedServer.port)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var warningCard: some View {
        AlertSectionCard(
            title: "启用说明",
            icon: "exclamationmark.triangle.fill",
            tint: .orange
        ) {
            AlertBullet(text: "启用后会向目标服务器写入脚本、配置文件和 cron 定时任务。")
            AlertBullet(text: "该任务会在服务器上常驻运行，用于 7x24 小时检测 CPU 使用率。")
            AlertBullet(text: "目标服务器需要能访问外网，否则无法通过 Bark 发出通知。")
            AlertBullet(text: "Bark 推送地址会保存在目标服务器，请仅在你信任的服务器上启用。")
        }
    }

    private var barkSetupCard: some View {
        AlertSectionCard(title: "Bark 配置", icon: "iphone.gen3.radiowaves.left.and.right") {
            HStack(spacing: 12) {
                Button("下载 Bark") {
                    openURL(barkAppStoreURL)
                }
                .buttonStyle(.bordered)

                Button("获取说明") {
                    showBarkHelp = true
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Bark 测试地址")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("https://api.day.app/xxxxxx", text: $barkURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("请先在 iPhone 安装 Bark，打开 Bark 后复制测试地址，再粘贴到这里。支持官方 Bark 和自建 bark-server。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var configurationCard: some View {
        AlertSectionCard(title: "CPU 告警配置", icon: "cpu.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("告警阈值")
                    Spacer()
                    Text("\(cpuThreshold)%")
                        .foregroundColor(.secondary)
                }
                Stepper("CPU 使用率超过 \(cpuThreshold)% 时告警", value: $cpuThreshold, in: 1...100)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("冷却时间")
                    Spacer()
                    Text("\(cooldownMinutes) 分钟")
                        .foregroundColor(.secondary)
                }
                Stepper("重复告警至少间隔 \(cooldownMinutes) 分钟", value: $cooldownMinutes, in: 1...120)
            }

            Text("检查频率固定为每分钟一次。首次越过阈值时会发送 Bark，持续高负载期间会遵循冷却时间避免刷屏。")
                .font(.footnote)
                .foregroundColor(.secondary)

            if hasUnsavedChanges {
                Button("保存本地配置") {
                    saveLocalConfiguration()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var statusCard: some View {
        AlertSectionCard(title: "远端状态", icon: "waveform.path.ecg") {
            statusRow(label: "部署状态", value: selectedStatus?.isInstalled == true ? "已启用" : "未启用")
            statusRow(label: "定时方式", value: selectedStatus?.scheduleDescription ?? "cron every minute")
            statusRow(label: "脚本路径", value: selectedStatus?.scriptPath ?? "~/.ios-monitor/cpu_alert.sh")

            if let lastCheckedAt = selectedStatus?.lastCheckedAt {
                statusRow(label: "最近检查", value: format(date: lastCheckedAt))
            }

            if let lastUpdatedAt = selectedStatus?.lastUpdatedAt {
                statusRow(label: "最近操作", value: format(date: lastUpdatedAt))
            }

            Text(selectedStatus?.summaryText ?? "尚未检查远端告警状态")
                .font(.footnote)
                .foregroundColor(selectedStatus?.lastError == nil ? .secondary : .red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actionsCard: some View {
        AlertSectionCard(title: "操作", icon: "bolt.badge.clock") {
            Button {
                Task { await refreshRemoteStatus() }
            } label: {
                actionLabel("刷新远端状态", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(isBusy)

            Button {
                Task { await sendTestNotification() }
            } label: {
                actionLabel("发送测试通知", systemImage: "paperplane")
            }
            .buttonStyle(.bordered)
            .disabled(isBusy || !barkURLIsFilled)

            Button {
                showInstallConfirmation = true
            } label: {
                actionLabel(
                    selectedStatus?.isInstalled == true ? "更新远端告警" : "安装并启用远端告警",
                    systemImage: "bell.badge"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || !barkURLIsFilled)

            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                actionLabel("卸载远端告警", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(isBusy || selectedStatus?.isInstalled != true)
        }
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        HStack {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
            }
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func syncSelection() {
        if let selectedServerID,
           store.servers.contains(where: { $0.id == selectedServerID }) {
            return
        }
        selectedServerID = store.servers.first?.id
    }

    private func loadForm(from config: ServerConfig) {
        barkURL = config.barkURL
        cpuThreshold = config.cpuAlertThreshold
        cooldownMinutes = config.cpuAlertCooldownMinutes
    }

    private func saveLocalConfiguration() {
        guard let selectedServer else { return }
        store.updateAlertSettings(
            for: selectedServer.id,
            barkURL: barkURL,
            cpuAlertThreshold: cpuThreshold,
            cpuAlertCooldownMinutes: cooldownMinutes
        )
    }

    private func refreshRemoteStatus() async {
        guard let selectedServer else { return }
        saveLocalConfiguration()
        guard let latestServer = store.servers.first(where: { $0.id == selectedServer.id }) else { return }
        await store.refreshRemoteAlertStatus(for: latestServer)
    }

    private func sendTestNotification() async {
        guard let selectedServer else { return }
        saveLocalConfiguration()
        guard let latestServer = store.servers.first(where: { $0.id == selectedServer.id }) else { return }
        await store.sendRemoteAlertTest(for: latestServer)
    }

    private func installRemoteAlert() async {
        guard let selectedServer else { return }
        saveLocalConfiguration()
        guard let latestServer = store.servers.first(where: { $0.id == selectedServer.id }) else { return }
        await store.deployRemoteAlert(for: latestServer)
    }

    private func removeRemoteAlert() async {
        guard let selectedServer else { return }
        await store.removeRemoteAlert(for: selectedServer)
    }

    private func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct AlertSectionCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = .blue
    let content: Content

    init(
        title: String,
        icon: String,
        tint: Color = .blue,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                Text(title)
                    .font(.headline)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AlertBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.orange)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

private struct BarkHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("获取 Bark 测试地址") {
                    Text("1. 在 iPhone 上安装并打开 Bark。")
                    Text("2. 在 Bark 首页复制测试地址。")
                    Text("3. 返回本 App，把测试地址粘贴到“Bark 测试地址”输入框。")
                }

                Section("说明") {
                    Text("你粘贴的地址会被转换成 Bark 推送地址，并保存到目标服务器上的远端告警配置中。")
                    Text("发送测试通知时，请确保目标服务器可以访问外网。")
                }
            }
            .navigationTitle("Bark 帮助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
