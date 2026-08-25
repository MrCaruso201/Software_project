import SwiftUI

/// Entry point della vista dedicata a un singolo evento.
/// Determina quale UI mostrare in base al ruolo dell'utente,
/// esattamente come fa `LiveRootView` per la sezione Live.
struct EventRootView: View {
    let server: DiscoveredServer
    let event: RaceEvent

    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = EventiViewModel()

    private var isAdmin: Bool {
        authState.currentUser?.role.canManageUsers == true
    }

    var body: some View {
        Group {
            if isAdmin {
                AdminEventView(server: server, event: event, viewModel: viewModel)
            } else {
                UserEventView(server: server, event: event, viewModel: viewModel)
            }
        }
        .onAppear {
            // Pre-carica le iscrizioni dell'utente corrente
            if let token = authState.currentToken {
                viewModel.fetchUserRegistrations(serverURL: server.httpURL, token: token)
            }
        }
    }
}
