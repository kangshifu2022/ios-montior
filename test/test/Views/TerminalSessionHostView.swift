import SwiftUI

struct TerminalSessionHostView: View {
    let server: ServerConfig
    @ObservedObject var viewModel: TerminalViewModel
    private let onSuspend: (() -> Void)?
    private let onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(
        server: ServerConfig,
        viewModel: TerminalViewModel,
        onSuspend: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.server = server
        self.viewModel = viewModel
        self.onSuspend = onSuspend
        self.onClose = onClose
    }

    var body: some View {
        Group {
            if shouldShowTerminalView {
                TerminalView(
                    server: server,
                    viewModel: viewModel,
                    onSuspend: onSuspend,
                    onClose: closeSession
                )
            } else {
                TerminalLaunchTransitionView(
                    server: server,
                    viewModel: viewModel,
                    onClose: closeSession
                )
            }
        }
        .animation(.easeInOut(duration: 0.22), value: shouldShowTerminalView)
        .task {
            viewModel.prepareLaunchIfNeeded()
            viewModel.connectIfNeeded()
        }
    }

    private var shouldShowTerminalView: Bool {
        if viewModel.isShowingLaunchSheet || viewModel.isShowingTmuxSessionPicker {
            return true
        }

        return viewModel.isTerminalReadyForPresentation
    }

    private func closeSession() {
        if let onClose {
            onClose()
            dismiss()
            return
        }

        viewModel.disconnect(clearError: true)
        dismiss()
    }
}

private struct TerminalLaunchTransitionView: View {
    let server: ServerConfig
    @ObservedObject var viewModel: TerminalViewModel
    let onClose: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private let steps: [TerminalConnectionStage] = [
        .preparing,
        .establishingSSH,
        .openingTerminal,
        .waitingForInitialOutput
    ]

    var body: some View {
        GeometryReader { proxy in
            let horizontalInset = min(max(proxy.size.width * 0.08, 20), 32)
            let cardWidth = min(352, max(proxy.size.width - (horizontalInset * 2), 292))

            ZStack {
                background
                    .ignoresSafeArea()

                ambientBackdrop
                    .ignoresSafeArea()

                VStack {
                    Spacer(minLength: 0)

                    windowCard
                        .frame(width: cardWidth)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, max(proxy.safeAreaInsets.top, 24))
            }
        }
    }

    private var windowCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            windowChrome

            VStack(alignment: .leading, spacing: 16) {
                identityBlock
                statusPanel
                stepsPanel
                footerNote

                if viewModel.showsConnectionFailureNotice {
                    retryButton
                        .padding(.top, 2)
                }
            }
            .padding(18)
        }
        .frame(minHeight: 316, alignment: .top)
        .background(windowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(windowBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: shadowColor, radius: 28, x: 0, y: 18)
    }

    private var windowChrome: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                chromeDot(.red.opacity(colorScheme == .dark ? 0.88 : 0.72))
                chromeDot(.yellow.opacity(colorScheme == .dark ? 0.9 : 0.76))
                chromeDot(.green.opacity(colorScheme == .dark ? 0.88 : 0.74))
            }
            .frame(width: 54, alignment: .leading)

            Spacer(minLength: 0)

            Text("终端连接")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(closeButtonForeground)
                    .frame(width: 24, height: 24)
                    .background(closeButtonBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭连接过渡窗口")
            .frame(width: 54, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(chromeBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(windowBorder)
                .frame(height: 1)
        }
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusPill

            Text(server.name)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)

            Text(endpointText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var statusPanel: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(colorScheme == .dark ? 0.18 : 0.12))
                    .frame(width: 54, height: 54)

                Circle()
                    .stroke(accentColor.opacity(colorScheme == .dark ? 0.36 : 0.18), lineWidth: 1)
                    .frame(width: 54, height: 54)

                if viewModel.showsConnectionFailureNotice {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.red)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(accentColor)
                        .scaleEffect(1.12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(primaryStatusTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(primaryStatusColor)

                Text(primaryStatusMessage)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(connectionStageLine)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusBadgeBackground)
                    .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var stepsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("连接步骤")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 0)

                Text(stepProgressText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(statusBadgeBackground)
                    .clipShape(Capsule())
            }

            ForEach(steps, id: \.rawValue) { step in
                TerminalLaunchStepRow(
                    title: step.title,
                    state: state(for: step)
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(panelBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var footerNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: viewModel.showsConnectionFailureNotice ? "arrow.clockwise.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(viewModel.showsConnectionFailureNotice ? accentColor : .secondary)
                .padding(.top, 1)

            Text(footerMessage)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(footerBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var retryButton: some View {
        Button(action: viewModel.reconnect) {
            Text("重新连接")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(retryForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(retryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var endpointText: String {
        "\(server.username)@\(server.host):\(server.port)"
    }

    private var primaryStatusTitle: String {
        if viewModel.showsConnectionFailureNotice {
            return "连接停在\(effectiveStage.title)"
        }

        return effectiveStage.title
    }

    private var primaryStatusMessage: String {
        if let issue = viewModel.lastConnectionIssueText, !issue.isEmpty {
            return issue
        }

        if let notice = viewModel.connectionNoticeText, !notice.isEmpty {
            return notice
        }

        return "正在准备终端会话…"
    }

    private var connectionStageLine: String {
        if viewModel.showsConnectionFailureNotice {
            return "当前卡在：\(effectiveStage.title)"
        }

        return "当前步骤：\(effectiveStage.title)"
    }

    private var stepProgressText: String {
        "\(currentStepOrdinal)/\(steps.count)"
    }

    private var currentStepOrdinal: Int {
        if viewModel.isTerminalReadyForPresentation || effectiveStage == .ready {
            return steps.count
        }

        guard let index = steps.firstIndex(of: effectiveStage) else {
            return 1
        }

        return max(1, index + 1)
    }

    private var effectiveStage: TerminalConnectionStage {
        if viewModel.connectionStage == .idle {
            return .preparing
        }

        return viewModel.connectionStage
    }

    private var accentColor: Color {
        viewModel.showsConnectionFailureNotice ? .red : Color(red: 0.13, green: 0.63, blue: 0.74)
    }

    private var primaryStatusColor: Color {
        viewModel.showsConnectionFailureNotice ? .red : .primary
    }

    private var retryBackground: Color {
        viewModel.showsConnectionFailureNotice
            ? accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14)
            : (colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
    }

    private var retryForeground: Color {
        colorScheme == .dark ? .white : .primary
    }

    private var background: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.12),
                    Color(red: 0.04, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.97, green: 0.98, blue: 1.0),
                Color(red: 0.93, green: 0.95, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var ambientBackdrop: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 28)
                .offset(x: -120, y: -180)

            Circle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.05))
                .frame(width: 180, height: 180)
                .blur(radius: 32)
                .offset(x: 130, y: 200)
        }
    }

    private var windowBackground: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.13, blue: 0.16),
                    Color(red: 0.08, green: 0.09, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.96),
                Color(red: 0.95, green: 0.97, blue: 0.99)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var chromeBackground: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.white.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color.white.opacity(0.84),
                Color.white.opacity(0.72)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var windowBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.07)
    }

    private var panelBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.04)
            : Color.black.opacity(0.03)
    }

    private var panelBorder: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.05)
    }

    private var statusBadgeBackground: Color {
        accentColor.opacity(colorScheme == .dark ? 0.22 : 0.12)
    }

    private var footerBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.035)
            : Color.black.opacity(0.035)
    }

    private var closeButtonBackground: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.05)
    }

    private var closeButtonForeground: Color {
        colorScheme == .dark ? Color.white.opacity(0.88) : Color.black.opacity(0.68)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.36)
            : Color.black.opacity(0.14)
    }

    private var footerMessage: String {
        if viewModel.showsConnectionFailureNotice {
            return "可以直接重试，或者关闭这个窗口，稍后再发起新的终端连接。"
        }

        return "如果长时间停留在某一步，基本就说明当前连接卡在这里。"
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentColor)
                .frame(width: 7, height: 7)

            Text(viewModel.statusText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(accentColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusBadgeBackground)
        .clipShape(Capsule())
    }

    private func chromeDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private func state(for step: TerminalConnectionStage) -> TerminalLaunchStepRow.State {
        let currentStage = effectiveStage

        if viewModel.showsConnectionFailureNotice {
            if step.rawValue < currentStage.rawValue {
                return .complete
            }
            if step == currentStage {
                return .failed
            }
            return .pending
        }

        if viewModel.isTerminalReadyForPresentation || currentStage == .ready {
            return .complete
        }

        if step.rawValue < currentStage.rawValue {
            return .complete
        }
        if step == currentStage {
            return .active
        }
        return .pending
    }
}

private struct TerminalLaunchStepRow: View {
    enum State {
        case complete
        case active
        case pending
        case failed
    }

    let title: String
    let state: State

    var body: some View {
        HStack(spacing: 10) {
            indicator
                .frame(width: 16, height: 16)

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(titleColor)

            Spacer(minLength: 0)

            if let badgeText {
                Text(badgeText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(badgeBackground)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(rowBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.green)
        case .active:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color(red: 0.13, green: 0.63, blue: 0.74))
                .scaleEffect(0.8)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color.secondary.opacity(0.5))
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.red)
        }
    }

    private var badgeText: String? {
        switch state {
        case .active:
            return "当前"
        case .failed:
            return "中断"
        case .complete, .pending:
            return nil
        }
    }

    private var badgeColor: Color {
        switch state {
        case .failed:
            return .red
        case .active:
            return Color(red: 0.13, green: 0.63, blue: 0.74)
        case .complete, .pending:
            return .clear
        }
    }

    private var badgeBackground: Color {
        switch state {
        case .failed:
            return Color.red.opacity(0.12)
        case .active:
            return Color(red: 0.13, green: 0.63, blue: 0.74).opacity(0.12)
        case .complete, .pending:
            return .clear
        }
    }

    private var titleColor: Color {
        switch state {
        case .complete:
            return .primary
        case .active:
            return Color(red: 0.13, green: 0.63, blue: 0.74)
        case .pending:
            return .primary
        case .failed:
            return .red
        }
    }

    private var rowBackground: Color {
        switch state {
        case .complete:
            return Color.green.opacity(0.08)
        case .active:
            return Color(red: 0.13, green: 0.63, blue: 0.74).opacity(0.1)
        case .pending:
            return Color.primary.opacity(0.04)
        case .failed:
            return Color.red.opacity(0.1)
        }
    }

    private var rowBorder: Color {
        switch state {
        case .complete:
            return Color.green.opacity(0.16)
        case .active:
            return Color(red: 0.13, green: 0.63, blue: 0.74).opacity(0.16)
        case .pending:
            return Color.primary.opacity(0.06)
        case .failed:
            return Color.red.opacity(0.16)
        }
    }
}
