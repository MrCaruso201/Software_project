import SwiftUI

/// Entry point della sezione Live. Determina quale UI mostrare in base al ruolo.
/// Usa una NavigationStack nativa con TabView nativa per uniformità con il resto dell'app.
struct LiveRootView: View {
    let server: DiscoveredServer
    let event: RaceEvent

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = LiveViewModel()

    private var isDirector: Bool {
        let role = authState.currentUser?.role
        return role == .admin || role == .raceDirector
    }

    var body: some View {
        Group {
            if isDirector {
                DirectorLiveView(event: event, viewModel: viewModel)
            } else {
                UserLiveView(event: event, viewModel: viewModel)
            }
        }
        .onAppear {
            viewModel.configure(
                serverURL: server.httpURL,
                token: authState.currentToken,
                eventId: event.id
            )
            if isDirector {
                viewModel.startPolling()
            } else {
                viewModel.startPollingMyKart()
            }
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}
