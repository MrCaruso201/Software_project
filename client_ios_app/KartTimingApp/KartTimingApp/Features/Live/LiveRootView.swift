import SwiftUI

/// Entry point della sezione Live. Determina quale UI mostrare in base al ruolo.
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
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if isDirector {
                DirectorLiveView(event: event, viewModel: viewModel, dismiss: dismiss)
            } else {
                UserLiveView(event: event, viewModel: viewModel, dismiss: dismiss)
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
