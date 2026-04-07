import SwiftUI

struct StandaloneTerminalView: View {
    let server: ServerConfig
    @StateObject private var viewModel: TerminalViewModel

    init(server: ServerConfig) {
        self.server = server
        _viewModel = StateObject(wrappedValue: TerminalViewModel(server: server))
    }

    var body: some View {
        TerminalView(server: server, viewModel: viewModel)
    }
}
