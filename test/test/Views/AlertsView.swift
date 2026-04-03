import SwiftUI

struct AlertsView: View {
    @ObservedObject var store: ServerStore

    @State private var selectedServerID: UUID?
    @State private var alertConfiguration = AlertConfiguration()
    @State private var showInstallConfirmation = false
    @State private var showRemoveConfirmation = false
    @State private var showBarkConfigurationSheet = false
    @State private var barkResultMessage = ""
    @State private var showBarkResultAlert = false

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

    private var barkConfigured: Bool {
        !store.alertSettings.barkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasUnsavedChanges: Bool {
        guard let selectedServer else { return false }
        return normalizedConfiguration(from: alertConfiguration) != selectedServer.alertConfiguration
    }

    private var canApplyAlert: Bool {
        barkConfigured && normalizedConfiguration(from: alertConfiguration).hasEnabledRules
    }

    private var websiteRuleNeedsURL: Bool {
        alertConfiguration.websiteEnabled &&
        AlertConfiguration.normalizedWebsiteURL(alertConfiguration.websiteURL).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.servers.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            currentServerCard
                            ruleConfigurationCard
                            statusCard
                            actionsCard
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("告警")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showBarkConfigurationSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("配置 Bark")
                }
            }
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
            .alert("保存并启用告警", isPresented: $showInstallConfirmation) {
                Button("取消", role: .cancel) {}
                Button("保存并启用") {
                    Task { await saveAndDeployAlert() }
                }
            } message: {
                Text("会把当前规则写入选中的服务器，并创建或更新服务器上的告警脚本与 cron 定时任务。")
            }
            .alert("取消告警", isPresented: $showRemoveConfirmation) {
                Button("取消", role: .cancel) {}
                Button("取消告警", role: .destructive) {
                    Task { await removeRemoteAlert() }
                }
            } message: {
                Text("会删除选中服务器上的告警脚本、配置文件和定时任务。")
            }
            .alert("Bark 测试结果", isPresented: $showBarkResultAlert) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(barkResultMessage)
            }
            .sheet(isPresented: $showBarkConfigurationSheet) {
                BarkConfigurationSheet(initialBarkURL: store.alertSettings.barkURL) { barkURL in
                    try await saveAndTestBark(url: barkURL)
                }
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
            Text("请先前往设置页面添加服务器。配置 Bark 的入口在告警页右上角的 +。")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }

    private var currentServerCard: some View {
        AlertSectionCard(title: "当前服务器", icon: "server.rack") {
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("当前正在为这台服务器配置告警")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(selectedServer.name)
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("\(selectedServer.username)@\(selectedServer.host):\(selectedServer.port)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        StatusPill(
                            title: barkConfigured ? "Bark 已配置" : "Bark 未配置",
                            tint: barkConfigured ? .green : .orange
                        )
                    }

                    Text("当前页面里勾选和保存的规则，只会作用于这台服务器。")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    if !barkConfigured {
                        Text("请先点右上角 + 配置 Bark 地址，然后再保存服务器告警。")
                            .font(.footnote)
                            .foregroundColor(.orange)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.blue.opacity(0.14), Color.cyan.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var ruleConfigurationCard: some View {
        AlertSectionCard(title: "告警规则", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("重复告警间隔")
                    Spacer()
                    Text("\(alertConfiguration.cooldownMinutes) 分钟")
                        .foregroundColor(.secondary)
                }

                Stepper(
                    "持续异常时，至少间隔 \(alertConfiguration.cooldownMinutes) 分钟再次通知",
                    value: $alertConfiguration.cooldownMinutes,
                    in: 1...120
                )
            }

            AlertRuleCard(
                title: "CPU 占用率",
                subtitle: "当 CPU 使用率持续高于阈值时通知",
                isEnabled: $alertConfiguration.cpuUsageEnabled
            ) {
                ThresholdEditor(
                    label: "CPU 阈值",
                    value: $alertConfiguration.cpuUsageThreshold
                )
            }

            AlertRuleCard(
                title: "内存占用率",
                subtitle: "当内存占用率高于阈值时通知",
                isEnabled: $alertConfiguration.memoryUsageEnabled
            ) {
                ThresholdEditor(
                    label: "内存阈值",
                    value: $alertConfiguration.memoryUsageThreshold
                )
            }

            AlertRuleCard(
                title: "CPU PSI(avg10)",
                subtitle: "使用 Linux PSI 的 avg10 指标监控 CPU 压力",
                isEnabled: $alertConfiguration.psiCPUEnabled
            ) {
                ThresholdEditor(
                    label: "CPU PSI 阈值",
                    value: $alertConfiguration.psiCPUThreshold
                )
            }

            AlertRuleCard(
                title: "内存 PSI(avg10)",
                subtitle: "使用 Linux PSI 的 avg10 指标监控内存压力",
                isEnabled: $alertConfiguration.psiMemoryEnabled
            ) {
                ThresholdEditor(
                    label: "内存 PSI 阈值",
                    value: $alertConfiguration.psiMemoryThreshold
                )
            }

            AlertRuleCard(
                title: "IO PSI(avg10)",
                subtitle: "使用 Linux PSI 的 avg10 指标监控 IO 压力",
                isEnabled: $alertConfiguration.psiIOEnabled
            ) {
                ThresholdEditor(
                    label: "IO PSI 阈值",
                    value: $alertConfiguration.psiIOThreshold
                )
            }

            AlertRuleCard(
                title: "网站连通性",
                subtitle: "例如监控 https://www.youtube.com 是否可以访问",
                isEnabled: $alertConfiguration.websiteEnabled
            ) {
                TextField("https://www.youtube.com", text: $alertConfiguration.websiteURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("可以直接填完整 URL，也可以只填域名，例如 `www.youtube.com`。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if websiteRuleNeedsURL {
                Text("已开启网站连通性监控，但还没有填写网址。")
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            if !normalizedConfiguration(from: alertConfiguration).hasEnabledRules {
                Text("至少选择一项告警规则，才能保存到服务器。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("当前将保存的规则")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if normalizedConfiguration(from: alertConfiguration).enabledRuleDescriptions.isEmpty {
                    Text("还没有启用任何规则")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(normalizedConfiguration(from: alertConfiguration).enabledRuleDescriptions, id: \.self) { item in
                        Text(item)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
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
                showInstallConfirmation = true
            } label: {
                actionLabel("保存并启用告警", systemImage: "bell.badge")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || !canApplyAlert)

            if hasUnsavedChanges {
                Text("当前规则有未保存修改，点击“保存并启用告警”后会同步到服务器。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if !barkConfigured {
                Text("未配置 Bark，无法启用远端告警。请点右上角 + 完成 Bark 连通性测试。")
                    .font(.footnote)
                    .foregroundColor(.orange)
            } else if !normalizedConfiguration(from: alertConfiguration).hasEnabledRules {
                Text("至少选择一项告警规则后，才能保存并启用。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Button(role: .destructive) {
                showRemoveConfirmation = true
            } label: {
                actionLabel("取消告警", systemImage: "trash")
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
        alertConfiguration = config.alertConfiguration
    }

    private func saveLocalConfiguration() {
        guard let selectedServer else { return }
        let normalized = normalizedConfiguration(from: alertConfiguration)
        alertConfiguration = normalized
        store.updateAlertSettings(
            for: selectedServer.id,
            alertConfiguration: normalized
        )
    }

    private func refreshRemoteStatus() async {
        guard let selectedServer else { return }
        saveLocalConfiguration()
        guard let latestServer = store.servers.first(where: { $0.id == selectedServer.id }) else { return }
        await store.refreshRemoteAlertStatus(for: latestServer)
    }

    private func saveAndDeployAlert() async {
        guard let selectedServer else { return }
        saveLocalConfiguration()
        guard let latestServer = store.servers.first(where: { $0.id == selectedServer.id }) else { return }
        await store.deployRemoteAlert(for: latestServer)
    }

    private func removeRemoteAlert() async {
        guard let selectedServer else { return }
        await store.removeRemoteAlert(for: selectedServer)
    }

    private func saveAndTestBark(url: String) async throws {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BarkService.BarkError(message: "请输入 Bark 测试地址")
        }

        store.updateGlobalAlertSettings(barkURL: trimmed)
        let message = try await BarkService.sendConfigurationTest(rawURL: trimmed)
        barkResultMessage = message
        showBarkResultAlert = true
    }

    private func normalizedConfiguration(from configuration: AlertConfiguration) -> AlertConfiguration {
        AlertConfiguration(
            cooldownMinutes: configuration.cooldownMinutes,
            cpuUsageEnabled: configuration.cpuUsageEnabled,
            cpuUsageThreshold: configuration.cpuUsageThreshold,
            memoryUsageEnabled: configuration.memoryUsageEnabled,
            memoryUsageThreshold: configuration.memoryUsageThreshold,
            psiCPUEnabled: configuration.psiCPUEnabled,
            psiCPUThreshold: configuration.psiCPUThreshold,
            psiMemoryEnabled: configuration.psiMemoryEnabled,
            psiMemoryThreshold: configuration.psiMemoryThreshold,
            psiIOEnabled: configuration.psiIOEnabled,
            psiIOThreshold: configuration.psiIOThreshold,
            websiteEnabled: configuration.websiteEnabled,
            websiteURL: configuration.websiteURL
        )
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

private struct StatusPill: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ThresholdEditor: View {
    let label: String
    @Binding var value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value)%")
                    .foregroundColor(.secondary)
            }

            Stepper("\(label)达到 \(value)% 时告警", value: $value, in: 1...100)
        }
    }
}

private struct AlertRuleCard<Content: View>: View {
    let title: String
    let subtitle: String
    @Binding var isEnabled: Bool
    let content: Content

    init(
        title: String,
        subtitle: String,
        isEnabled: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isEnabled = isEnabled
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $isEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if isEnabled {
                content
            }
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BarkConfigurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @FocusState private var barkURLFocused: Bool

    @State private var barkURL: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let barkAppStoreURL = URL(string: "https://apps.apple.com/app/id1403753865")!
    let onSaveAndTest: (String) async throws -> Void

    init(
        initialBarkURL: String,
        onSaveAndTest: @escaping (String) async throws -> Void
    ) {
        self._barkURL = State(initialValue: initialBarkURL)
        self.onSaveAndTest = onSaveAndTest
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bark 地址") {
                    TextField("https://api.day.app/xxxxxx", text: $barkURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($barkURLFocused)

                    Text("保存时会立刻从 App 端测试 Bark 连通性，发送内容固定为“bark通知成功配置”。")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                Section("获取方式") {
                    Button("下载 Bark") {
                        openURL(barkAppStoreURL)
                    }

                    Text("1. 在 iPhone 上安装并打开 Bark。")
                    Text("2. 在 Bark 首页复制测试地址。")
                    Text("3. 回到这里粘贴并保存。")
                }

                if let errorMessage, !errorMessage.isEmpty {
                    Section("测试结果") {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("配置 Bark")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSaving ? "测试中..." : "保存并测试") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                barkURLFocused = barkURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await onSaveAndTest(barkURL)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
