import SwiftUI
import UIKit
import SwiftTerm

struct TerminalSurfaceView: UIViewRepresentable {
    @ObservedObject var viewModel: TerminalViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.backgroundColor = .black
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.terminalView = terminalView

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
            terminalView.becomeFirstResponder()
        }

        return terminalView
    }

    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        context.coordinator.terminalView = uiView
    }

    static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.viewModel.detachOutputSink()
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
