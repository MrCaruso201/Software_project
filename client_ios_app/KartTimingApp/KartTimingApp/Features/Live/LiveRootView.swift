import SwiftUI

/// Entry point della sezione Live. Determina quale UI mostrare in base al ruolo.
/// Usa una NavigationStack nativa con TabView nativa per uniformità con il resto dell'app.
struct LiveRootView: View {
    let server: DiscoveredServer
    let event: RaceEvent

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = LiveViewModel()
    @StateObject private var timingManager = KartTimingManager()
    @State private var trackLoadError: String? = nil

    private var isDirector: Bool {
        let role = authState.currentUser?.role
        return role == .admin || role == .raceDirector
    }

    var body: some View {
        Group {
            if isDirector {
                DirectorLiveView(event: event, viewModel: viewModel)
                    .environmentObject(timingManager)
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
                connectTimingManager()
            } else {
                viewModel.startPollingMyKart()
            }
        }
        .onDisappear {
            viewModel.stopPolling()
            timingManager.disconnect()
        }
    }

    private func connectTimingManager() {
        guard let token = authState.currentToken else { return }
        let base = AppEnvironment.shared.baseURL
        Task {
            do {
                let kartodromi = try await KartodromoService.fetchKartodromi(
                    baseURL: base,
                    accessToken: token
                )
                if let matched = kartodromi.first(where: { $0.nome == event.location }) {
                    timingManager.connect(to: server)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        timingManager.sendCommand("set_url", extra: ["url": matched.url])
                    }
                } else {
                    trackLoadError = "Impossibile trovare l'URL per la pista: \(event.location)"
                }
            } catch {
                trackLoadError = error.localizedDescription
            }
        }
    }
}
