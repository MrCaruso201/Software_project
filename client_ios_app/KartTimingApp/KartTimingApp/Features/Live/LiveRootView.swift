import SwiftUI

/// Entry point della sezione Live. Determina quale UI mostrare in base al ruolo.
/// Usa una NavigationStack nativa con TabView nativa per uniformità con il resto dell'app.
struct LiveRootView: View {
    let server: DiscoveredServer
    let event: RaceEvent
    /// Indica se l'utente ha una registrazione confermata all'evento.
    /// Se false, la vista utente mostra solo la classifica (no Team View, no Pilot button).
    var isUserRegistered: Bool = true

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = LiveViewModel()
    @StateObject private var timingManager = KartTimingManager()
    @State private var connectedTrackId: Int?
    @State private var trackLoadError: String? = nil
    @State private var isLoadingConnection = false
    @State private var connectionTask: Task<Void, Never>?

    private var isDirector: Bool {
        let role = authState.currentUser?.role
        return role == .admin || role == .raceDirector
    }

    var body: some View {
        Group {
            if isDirector {
                DirectorLiveView(event: event, viewModel: viewModel,
                    isReconnecting: isLoadingConnection, reconnect: connectTimingManager)
                    .environmentObject(timingManager)
            } else {
                UserLiveView(event: event, viewModel: viewModel,
                    isReconnecting: isLoadingConnection, reconnect: connectTimingManager,
                    isUserRegistered: isUserRegistered)
                    .environmentObject(timingManager)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if !timingManager.isConnected {
                HStack(spacing: 12) {
                    Text(trackLoadError ?? (isLoadingConnection || timingManager.isConnecting
                        ? "Connessione in corso…" : "Connessione live interrotta"))
                        .font(.footnote)
                    Spacer()
                    Button(action: connectTimingManager) {
                        Label("Riconnetti", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoadingConnection || timingManager.isConnecting)
                    .tint(.kartAccent)
                }
                .padding(12)
                .background(Color.kartPanel)
            }
        }
        .onChange(of: timingManager.isConnected) { _, connected in
            if connected { Task { await viewModel.fetchAll() } }
        }
        .onAppear {
            viewModel.configure(
                serverURL: server.httpURL,
                token: authState.currentToken,
                eventId: event.id,
                isDirector: isDirector,
                timingManager: timingManager
            )
            if isDirector {
                viewModel.startPolling()
            } else {
                viewModel.startPollingMyKart()
            }
            connectTimingManager()
        }
        .onDisappear {
            connectionTask?.cancel()
            connectionTask = nil
            isLoadingConnection = false
            viewModel.stopPolling()
            timingManager.disconnect()
        }
    }

    private func connectTimingManager() {
        guard !isLoadingConnection, !timingManager.isConnecting,
              let token = authState.currentToken else { return }
        trackLoadError = nil
        isLoadingConnection = true
        let base = AppEnvironment.shared.baseURL
        connectionTask = Task { @MainActor in
            defer { isLoadingConnection = false }
            do {
                let kartodromi = try await KartodromoService.fetchKartodromi(
                    baseURL: base,
                    accessToken: token
                )
                try Task.checkCancellation()
                if let matched = kartodromi.first(where: {
                    if let connectedTrackId { return $0.id == connectedTrackId }
                    return $0.nome == event.location || "\($0.nome) - \($0.luogo)" == event.location
                }) {
                    connectedTrackId = matched.id
                    timingManager.connect(to: server)
                    timingManager.sendCommand("set_url", extra: ["url": matched.url])
                    timingManager.subscribeToEvent(event.id)
                } else {
                    trackLoadError = "Impossibile trovare l'URL per la pista: \(event.location)"
                }
            } catch {
                guard !Task.isCancelled else { return }
                trackLoadError = error.localizedDescription
            }
        }
    }
}
