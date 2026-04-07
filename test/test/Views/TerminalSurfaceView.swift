import SwiftUI
import UIKit
import SwiftTerm

struct TerminalSurfaceView: UIViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = ScrollbackTerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView
        terminalView.allowMouseReporting = false
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
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.terminalView = uiView
        uiView.allowMouseReporting = false
        uiView.inputAccessoryView = makeShortcutAccessory(for: uiView)
        applyAppearance(to: uiView)
        uiView.reloadInputViews()

        if context.coordinator.lastKeyboardFocusRequestID != viewModel.keyboardFocusRequestID {
            context.coordinator.lastKeyboardFocusRequestID = viewModel.keyboardFocusRequestID
            (uiView as? ScrollbackTerminalView)?.requestKeyboardFocus()
        }
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
        let scrollbackView = terminalView as? ScrollbackTerminalView

        func consumeAccessoryModifiers() -> (alt: Bool, shift: Bool) {
            let modifiers = (
                alt: scrollbackView?.accessoryAltModifier ?? false,
                shift: scrollbackView?.accessoryShiftModifier ?? false
            )

            if modifiers.alt {
                scrollbackView?.accessoryAltModifier = false
            }
            if modifiers.shift {
                scrollbackView?.accessoryShiftModifier = false
            }

            return modifiers
        }

        func sendShortcutBytes(_ bytes: [UInt8]) {
            viewModel.send(bytes: bytes)
        }

        func sendControlShortcut(_ byte: UInt8) {
            let modifiers = consumeAccessoryModifiers()
            var payload = [byte]
            if modifiers.alt {
                payload.insert(27, at: 0)
            }
            sendShortcutBytes(payload)
        }

        func sendShortcutText(_ text: String, shiftedText: String? = nil, supportsShift: Bool = true) {
            let modifiers = consumeAccessoryModifiers()
            let resolvedText: String
            if supportsShift, modifiers.shift {
                resolvedText = shiftedText ?? text
            } else {
                resolvedText = text
            }

            var payload = Array(resolvedText.utf8)
            if modifiers.alt {
                payload.insert(27, at: 0)
            }
            sendShortcutBytes(payload)
        }

        func sendModifiedCSI(finalByte: UInt8, baseBytes: [UInt8], supportsShift: Bool = true) {
            let modifiers = consumeAccessoryModifiers()
            let alt = modifiers.alt
            let shift = supportsShift ? modifiers.shift : false

            guard alt || shift else {
                sendShortcutBytes(baseBytes)
                return
            }

            let modifierValue = 1 + (shift ? 1 : 0) + (alt ? 2 : 0)
            let payload: [UInt8] = [27, 91, 49, 59] + Array(String(modifierValue).utf8) + [finalByte]
            sendShortcutBytes(payload)
        }

        func sendTabShortcut() {
            let modifiers = consumeAccessoryModifiers()

            switch (modifiers.alt, modifiers.shift) {
            case (false, false):
                sendShortcutBytes([9])
            case (false, true):
                sendShortcutBytes([27, 91, 90])
            case (true, false):
                sendShortcutBytes([27, 9])
            case (true, true):
                sendShortcutBytes([27, 27, 91, 90])
            }
        }

        func pasteClipboardText() {
            _ = consumeAccessoryModifiers()
            guard let content = UIPasteboard.general.string, !content.isEmpty else { return }
            viewModel.send(text: content)
        }

        let topRow: [TerminalShortcutAccessoryView.ShortcutItem] = [
            .init(title: "ESC", preferredWidth: 38, action: {
                let modifiers = consumeAccessoryModifiers()
                let payload: [UInt8] = modifiers.alt ? [27, 27] : [27]
                sendShortcutBytes(payload)
            }),
            .init(title: "Exit", style: .accent, preferredWidth: 48, action: {
                let modifiers = consumeAccessoryModifiers()
                viewModel.sendExit()
                if modifiers.alt || modifiers.shift {
                    scrollbackView?.accessoryAltModifier = false
                    scrollbackView?.accessoryShiftModifier = false
                }
            }),
            .init(title: "-", preferredWidth: 30, action: {
                sendShortcutText("-", shiftedText: "_")
            }),
            .init(title: "|", preferredWidth: 30, action: {
                sendShortcutText("|")
            }),
            .init(title: "↑", preferredWidth: 30, action: {
                sendModifiedCSI(finalByte: 65, baseBytes: [27, 91, 65])
            }),
            .init(title: "/", preferredWidth: 30, action: {
                sendShortcutText("/", shiftedText: "?")
            }),
            .init(title: "PgUp", preferredWidth: 42, action: { [weak terminalView] in
                terminalView?.pageUp()
            }),
            .init(
                systemImageName: "doc.on.doc",
                accessibilityLabel: "粘贴剪贴板内容",
                preferredWidth: 34,
                action: {
                    pasteClipboardText()
                }
            ),
            .init(
                systemImageName: "keyboard",
                accessibilityLabel: "显示或隐藏系统键盘",
                style: .accent,
                preferredWidth: 34,
                action: { [weak terminalView] in
                    guard let terminalView else { return }
                    if let scrollbackView = terminalView as? ScrollbackTerminalView {
                        scrollbackView.toggleSoftwareKeyboard()
                    } else {
                        _ = terminalView.resignFirstResponder()
                    }
                }
            )
        ]

        let middleRow: [TerminalShortcutAccessoryView.ShortcutItem] = [
            .init(title: "Tab", preferredWidth: 64, action: {
                sendTabShortcut()
            }),
            .init(title: "\\", preferredWidth: 30, action: {
                sendShortcutText("\\", shiftedText: "|")
            }),
            .init(title: "←", preferredWidth: 30, action: {
                sendModifiedCSI(finalByte: 68, baseBytes: [27, 91, 68])
            }),
            .init(title: "↓", preferredWidth: 30, action: {
                sendModifiedCSI(finalByte: 66, baseBytes: [27, 91, 66])
            }),
            .init(title: "→", preferredWidth: 30, action: {
                sendModifiedCSI(finalByte: 67, baseBytes: [27, 91, 67])
            }),
            .init(title: "PgDn", preferredWidth: 42, action: { [weak terminalView] in
                terminalView?.pageDown()
            }),
            .init(
                title: "< >",
                accessibilityLabel: "脚本快捷键，暂未启用",
                preferredWidth: 72,
                action: {}
            )
        ]

        let bottomRow: [TerminalShortcutAccessoryView.ShortcutItem] = [
            .init(
                title: "Ctrl",
                accessibilityLabel: "切换 Ctrl 修饰键",
                preferredWidth: 40,
                isSelected: { [weak terminalView] in
                    terminalView?.controlModifier ?? false
                },
                observedNotifications: [
                    .init(name: .terminalViewControlModifierReset, objectProvider: { [weak terminalView] in
                        terminalView
                    })
                ],
                action: { [weak terminalView] in
                    guard let terminalView else { return }
                    terminalView.controlModifier.toggle()
                }
            ),
            .init(
                title: "Alt",
                accessibilityLabel: "切换 Alt 修饰键",
                preferredWidth: 40,
                isSelected: { [weak scrollbackView] in
                    scrollbackView?.accessoryAltModifier ?? false
                },
                observedNotifications: [
                    .init(name: .terminalAccessoryAltModifierChanged, objectProvider: { [weak scrollbackView] in
                        scrollbackView
                    })
                ],
                action: { [weak scrollbackView] in
                    scrollbackView?.accessoryAltModifier.toggle()
                }
            ),
            .init(
                title: "Shift",
                accessibilityLabel: "切换 Shift 修饰键",
                preferredWidth: 44,
                isSelected: { [weak scrollbackView] in
                    scrollbackView?.accessoryShiftModifier ?? false
                },
                observedNotifications: [
                    .init(name: .terminalAccessoryShiftModifierChanged, objectProvider: { [weak scrollbackView] in
                        scrollbackView
                    })
                ],
                action: { [weak scrollbackView] in
                    scrollbackView?.accessoryShiftModifier.toggle()
                }
            ),
            .init(title: "Ctrl+C", preferredWidth: 64, action: {
                sendControlShortcut(3)
            }),
            .init(title: "Ctrl+B", preferredWidth: 64, action: {
                sendControlShortcut(2)
            }),
            .init(title: "Home", preferredWidth: 42, action: {
                sendModifiedCSI(finalByte: 72, baseBytes: [27, 91, 72])
            }),
            .init(title: "End", preferredWidth: 38, action: {
                sendModifiedCSI(finalByte: 70, baseBytes: [27, 91, 70])
            })
        ]

        return TerminalShortcutAccessoryView(rows: [topRow, middleRow, bottomRow])
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
        var lastKeyboardFocusRequestID = 0

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
