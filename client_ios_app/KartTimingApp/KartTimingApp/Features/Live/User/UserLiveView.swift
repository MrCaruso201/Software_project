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
                ClassificaLiveView(viewModel: viewModel, exportRequested: .constant(false))
                    .tabItem { Label("Classifica", systemImage: "list.number") }

                // ── Tab 2: Team View (solo utenti registrati) ──────────
                if isUserRegistered {
                    TeamLiveView(viewModel: viewModel)
                        .tabItem { Label("Team View", systemImage: "person.3.fill") }
                }
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

                // ── Indicatore LIVE ───────────────────────────────────
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        if isStarted {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                        }
                        Text(isStarted ? "LIVE" : "IN ATTESA")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(isStarted ? .red : .gray)
                    }
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
                PilotLiveView(viewModel: viewModel)
            }
        }
    }
}
