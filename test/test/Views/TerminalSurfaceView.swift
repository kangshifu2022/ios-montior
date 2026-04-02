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
            terminalView.feed(byteArray: bytes)
        }

        DispatchQueue.main.async {
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
            // We keep the remote PTY at a fixed size for now.
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
    }
}
