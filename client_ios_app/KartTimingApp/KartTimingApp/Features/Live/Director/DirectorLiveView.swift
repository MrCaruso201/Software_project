import SwiftUI

/// Pannello principale Race Director con TabView nativa iOS.
struct DirectorLiveView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    private var isStarted: Bool { event.status == "started" }
    private var isFinished: Bool { event.status == "finished" }

    /// Trigger per l'export CSV: viene settato a true dalla toolbar,
    /// ClassificaLiveView lo osserva con onChange e avvia il download.
    @State private var csvExportRequested = false
    
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // ── Tab 1: Classifica ─────────────────────────────────
                ClassificaLiveView(isDirector: true, viewModel: viewModel, exportRequested: $csvExportRequested)
                    .tabItem { Label("Classifica", systemImage: "list.number") }
                    .tag(0)

                // ── Tab 2: Kart (Assegnazione) ────────────────────────
                AssegnazioneKartView(event: event, viewModel: viewModel)
                    .tabItem { Label("Kart", systemImage: "flag.2.crossed.fill") }
                    .tag(1)
                    
                // ── Tab 3: Gestione LIVE (Penalità + Controllo Gara) ─────────────
                GestioneLiveView(event: event, viewModel: viewModel)
                    .tabItem { Label("Gestione LIVE", systemImage: "exclamationmark.triangle.fill") }
                    .tag(2)

                // ── Tab 4: Pit Stop ───────────────────────────────────
                PitWallLiveView(viewModel: viewModel, event: event)
                    .tabItem { Label("Pit Stop", systemImage: "stopwatch.fill") }
                    .tag(3)

                // ── Tab 5: Messaggi ───────────────────────────────────
                DirectorMessaggiView(viewModel: viewModel)
                    .tabItem { Label("Messaggi", systemImage: "bubble.left.and.bubble.right.fill") }
                    .tag(4)
            }
            .tint(.kartAccent)
            .navigationTitle(viewModel.currentSessionName ?? event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // ── Chiudi ────────────────────────────────────────────
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }

                // ── Titolo evento ────────────────────────────────────
                ToolbarItem(placement: .principal) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.kartForeground)
                        .lineLimit(1)
                }

                // ── Esporta classifica CSV (solo admin/director) ───────
                ToolbarItem(placement: .navigationBarTrailing) {
                    if selectedTab == 0 {
                        Button {
                            csvExportRequested = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.kartAccent)
                    }
                }
            }
        }
    }
}
