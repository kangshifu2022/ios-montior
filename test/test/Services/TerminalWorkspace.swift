import Combine
import Foundation

@MainActor
final class TerminalWorkspace: ObservableObject {
    @Published private(set) var sessions: [TerminalWorkspaceSession] = []
    @Published var presentedSession: TerminalWorkspaceSession?

    private var dismissObservers: [UUID: AnyCancellable] = [:]

    var suspendedSessions: [TerminalWorkspaceSession] {
        Array(sessions.reversed()).filter { $0.id != presentedSession?.id }
    }

    func presentTerminal(for server: ServerConfig) {
        if let existingSession = sessions.first(where: { $0.server.id == server.id }) {
            presentedSession = existingSession
            return
        }

        let session = TerminalWorkspaceSession(server: server)
        sessions.append(session)
        observeLifecycle(of: session)
        presentedSession = session
    }

    func resume(_ session: TerminalWorkspaceSession) {
        guard sessions.contains(where: { $0.id == session.id }) else { return }
        presentedSession = session
    }

    func suspend(_ session: TerminalWorkspaceSession) {
        guard presentedSession?.id == session.id else { return }
        presentedSession = nil
    }

    func close(_ session: TerminalWorkspaceSession) {
        session.viewModel.disconnect(clearError: true)
        remove(session)
    }

    func closeSessions(forServerID serverID: UUID) {
        let matchingSessions = sessions.filter { $0.server.id == serverID }
        for session in matchingSessions {
            close(session)
        }
    }

    private func observeLifecycle(of session: TerminalWorkspaceSession) {
        dismissObservers[session.id] = session.viewModel.$shouldDismissTerminal
            .removeDuplicates()
            .sink { [weak self] shouldDismiss in
                guard shouldDismiss else { return }
                self?.handleDismissRequest(for: session)
            }
    }

    private func handleDismissRequest(for session: TerminalWorkspaceSession) {
        session.viewModel.acknowledgeDismissRequest()
        remove(session)
    }

    private func remove(_ session: TerminalWorkspaceSession) {
        if presentedSession?.id == session.id {
            presentedSession = nil
        }

        dismissObservers[session.id]?.cancel()
        dismissObservers.removeValue(forKey: session.id)
        sessions.removeAll { $0.id == session.id }
    }
}

final class TerminalWorkspaceSession: Identifiable {
    let id = UUID()
    let server: ServerConfig
    let viewModel: TerminalViewModel

    init(server: ServerConfig) {
        self.server = server
        self.viewModel = TerminalViewModel(server: server)
    }
}
