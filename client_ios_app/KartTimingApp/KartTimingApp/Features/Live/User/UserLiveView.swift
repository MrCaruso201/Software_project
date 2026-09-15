import SwiftUI

/// Vista Live per i piloti/componenti del team con TabView nativa iOS.
struct UserLiveView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    /// Se false (utente non iscritto all'evento), mostra solo la Classifica
    /// e nasconde sia il tab "Team View" sia il pulsante Pilot View.
    var isUserRegistered: Bool = true

    @Environment(\.dismiss) private var dismiss

    @State private var navigateToPilot: Bool = false

    private var isStarted: Bool { event.status == "started" }

    var body: some View {
        NavigationStack {
            TabView {
                // ── Tab 1: Classifica ─────────────────────────────────
                ClassificaLiveView(isDirector: false, viewModel: viewModel, exportRequested: .constant(false))
                    .tabItem { Label("Classifica", systemImage: "list.number") }

                // ── Tab 2: Team View (solo utenti registrati) ──────────
                if isUserRegistered {
                    TeamLiveView(event: event, viewModel: viewModel)
                        .tabItem { Label("Team View", systemImage: "person.3.fill") }
                }

                // ── Tab 3: Messaggi ────────────────────────────────────
                UserMessaggiView(viewModel: viewModel)
                    .tabItem { Label("Messaggi", systemImage: "bubble.left.and.bubble.right.fill") }
            }
            .tint(.kartNavigationTint)
            .navigationTitle(viewModel.currentSessionName ?? event.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // ── Chiudi ────────────────────────────────────────────
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartForeground)
                }

                // ── Titolo evento ────────────────────────────────────
                ToolbarItem(placement: .principal) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.kartForeground)
                        .lineLimit(1)
                }

                // ── Pulsante Pilot View (solo utenti registrati) ───────
                if isUserRegistered {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            navigateToPilot = true
                        } label: {
                            Image(systemName: "car.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $navigateToPilot) {
                PilotLiveView(viewModel: viewModel, event: event)
            }
        }
    }
}
