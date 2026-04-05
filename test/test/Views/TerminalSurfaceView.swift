import SwiftUI
import UIKit
import SwiftTerm

struct TerminalSurfaceView: UIViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel
    let colorScheme: ColorScheme

    private typealias ShortcutModifier = TerminalShortcutAccessoryView.Modifier

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView
        terminalView.inputAccessoryView = makeShortcutAccessory(for: terminalView)
        applyAppearance(to: terminalView)

        viewModel.attachOutputSink { [weak terminalView] bytes in
            guard let terminalView else { return }
            terminalView.feed(byteArray: ArraySlice(bytes))
        }

        DispatchQueue.main.async {
            let terminal = terminalView.getTerminal()
            context.coordinator.pushTerminalSize(
                from: terminalView,
                columns: terminal.cols,
                rows: terminal.rows
            )
            viewModel.connectIfNeeded()
            _ = terminalView.becomeFirstResponder()
            terminalView.reloadInputViews()
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.terminalView = uiView
        uiView.inputAccessoryView = makeShortcutAccessory(for: uiView)
        applyAppearance(to: uiView)
        uiView.reloadInputViews()
    }

    static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.viewModel.detachOutputSink()
    }

    private func applyAppearance(to terminalView: SwiftTerm.TerminalView) {
        let palette = Self.palette(for: colorScheme)
        terminalView.backgroundColor = palette.background
        terminalView.nativeBackgroundColor = palette.background
        terminalView.nativeForegroundColor = palette.foreground
        terminalView.caretColor = palette.caret
        terminalView.selectedTextBackgroundColor = palette.selection
    }

    private func makeShortcutAccessory(for terminalView: SwiftTerm.TerminalView) -> UIView {
        TerminalShortcutAccessoryView(terminalView: terminalView, rows: [
            [
                .init(title: "Esc", action: { _ in viewModel.sendEscape() }),
                .init(modifier: .alt),
                .init(title: "Home", action: { modifiers in sendHome(using: modifiers) }),
                .init(title: "↑", action: { modifiers in sendArrowUp(using: modifiers) }),
                .init(title: "End", action: { modifiers in sendEnd(using: modifiers) }),
                .init(title: "exit", action: { _ in viewModel.sendExit() })
            ],
            [
                .init(title: "Tab", action: { modifiers in sendTab(using: modifiers) }),
                .init(modifier: .control),
                .init(title: "←", action: { modifiers in sendArrowLeft(using: modifiers) }),
                .init(title: "↓", action: { modifiers in sendArrowDown(using: modifiers) }),
                .init(title: "→", action: { modifiers in sendArrowRight(using: modifiers) }),
                .init(systemImageName: "doc.on.clipboard", accessibilityLabel: "粘贴", action: { _ in pasteClipboardContents() }),
                .init(systemImageName: "keyboard.chevron.compact.down", accessibilityLabel: "收起键盘", action: { _ in terminalView.resignFirstResponder() })
            ],
            [
                .init(modifier: .shift)
            ]
        ])
    }

    private func pasteClipboardContents() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else {
            return
        }

        viewModel.send(text: text)
    }

    private func sendTab(using modifiers: Set<ShortcutModifier>) {
        guard let modifierValue = modifierValue(for: modifiers) else {
            viewModel.sendTab()
            return
        }

        if modifiers == Set([ShortcutModifier.shift]) {
            viewModel.send(text: "\u{1B}[Z")
            return
        }

        viewModel.send(text: "\u{1B}[1;\(modifierValue)I")
    }

    private func sendHome(using modifiers: Set<ShortcutModifier>) {
        sendCursorKey(final: "H", modifiers: modifiers) {
            viewModel.sendHome()
        }
    }

    private func sendEnd(using modifiers: Set<ShortcutModifier>) {
        sendCursorKey(final: "F", modifiers: modifiers) {
            viewModel.sendEnd()
        }
    }

    private func sendArrowUp(using modifiers: Set<ShortcutModifier>) {
        sendCursorKey(final: "A", modifiers: modifiers) {
            viewModel.sendArrowUp()
        }
    }

    private func sendArrowDown(using modifiers: Set<ShortcutModifier>) {
        sendCursorKey(final: "B", modifiers: modifiers) {
            viewModel.sendArrowDown()
        }
    }

    private func sendArrowRight(using modifiers: Set<ShortcutModifier>) {
        sendCursorKey(final: "C", modifiers: modifiers) {
            viewModel.sendArrowRight()
        }
    }

    private func sendArrowLeft(using modifiers: Set<ShortcutModifier>) {
        sendCursorKey(final: "D", modifiers: modifiers) {
            viewModel.sendArrowLeft()
        }
    }

    private func sendCursorKey(final: Character, modifiers: Set<ShortcutModifier>, fallback: () -> Void) {
        guard let modifierValue = modifierValue(for: modifiers) else {
            fallback()
            return
        }

        viewModel.send(text: "\u{1B}[1;\(modifierValue)\(final)")
    }

    private func modifierValue(for modifiers: Set<ShortcutModifier>) -> Int? {
        guard !modifiers.isEmpty else {
            return nil
        }

        var value = 1
        if modifiers.contains(.shift) {
            value += 1
        }
        if modifiers.contains(.alt) {
            value += 2
        }
        if modifiers.contains(.control) {
            value += 4
        }
        return value
    }

    private static func palette(for colorScheme: ColorScheme) -> TerminalPalette {
        switch colorScheme {
        case .dark:
            return TerminalPalette(
                background: UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0),
                foreground: UIColor(red: 0.89, green: 0.92, blue: 0.96, alpha: 1.0),
                caret: UIColor(red: 0.40, green: 0.80, blue: 1.0, alpha: 1.0),
                selection: UIColor(red: 0.22, green: 0.39, blue: 0.61, alpha: 0.45)
            )
        case .light:
            return TerminalPalette(
                background: UIColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0),
                foreground: UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1.0),
                caret: UIColor(red: 0.00, green: 0.42, blue: 0.88, alpha: 1.0),
                selection: UIColor(red: 0.56, green: 0.74, blue: 0.98, alpha: 0.45)
            )
        @unknown default:
            return palette(for: .light)
        }
    }

    private struct TerminalPalette {
        let background: UIColor
        let foreground: UIColor
        let caret: UIColor
        let selection: UIColor
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let viewModel: TerminalViewModel
        weak var terminalView: SwiftTerm.TerminalView?

        init(viewModel: TerminalViewModel) {
            self.viewModel = viewModel
        }

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            viewModel.send(bytes: Array(data))
        }

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            pushTerminalSize(from: source, columns: newCols, rows: newRows)
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            viewModel.updateTerminalTitle(title)
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String : String]) {
            guard let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
        }

        func bell(source: SwiftTerm.TerminalView) {}

        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            UIPasteboard.general.setData(content, forPasteboardType: "public.utf8-plain-text")
        }

        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}

        func pushTerminalSize(from source: SwiftTerm.TerminalView, columns: Int, rows: Int) {
            let scale = source.window?.screen.scale ?? UIScreen.main.scale
            let pixelWidth = Int(source.bounds.width * scale)
            let pixelHeight = Int(source.bounds.height * scale)

            viewModel.updateTerminalSize(
                columns: columns,
                rows: rows,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight
            )
        }
    }
}
