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

    var body: some View {
        NavigationStack {
            TabView {
                // ── Tab 1: Classifica ─────────────────────────────────
                ClassificaLiveView(viewModel: viewModel, exportRequested: $csvExportRequested)
                    .tabItem { Label("Classifica", systemImage: "list.number") }

                // ── Tab 2: Kart (Assegnazione) ────────────────────────
                KartAssignmentView(event: event, viewModel: viewModel)
                    .tabItem { Label("Kart", systemImage: "flag.2.crossed.fill") }
                    
                // ── Tab 3: Gestione LIVE (Penalità + Controllo Gara) ─────────────
                KartPenaltyView(event: event, viewModel: viewModel)
                    .tabItem { Label("Gestione LIVE", systemImage: "exclamationmark.triangle.fill") }

                // ── Tab 4: Messaggi ───────────────────────────────────
                MessaggiView(viewModel: viewModel)
                    .tabItem { Label("Messaggi", systemImage: "bubble.left.and.bubble.right.fill") }
            }
            .tint(.kartAccent)
            .navigationTitle(event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                // ── Chiudi ────────────────────────────────────────────
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }

                // ── Indicatore LIVE + stato ───────────────────────────
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        if isStarted {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                        }
                        Text(isStarted ? "LIVE" : isFinished ? "TERMINATA" : "IN ATTESA")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(isStarted ? .red : .gray)
                    }
                }

                // ── Esporta classifica CSV (solo admin/director) ───────
                ToolbarItem(placement: .navigationBarTrailing) {
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
