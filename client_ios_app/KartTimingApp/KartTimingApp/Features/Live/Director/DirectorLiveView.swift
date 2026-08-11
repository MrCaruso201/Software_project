import SwiftUI

/// Pannello principale Race Director con TabView nativa iOS.
struct DirectorLiveView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var showStatusConfirm = false
    @State private var pendingStatus: String? = nil

    private var isStarted: Bool { event.status == "started" }
    private var isFinished: Bool { event.status == "finished" }
    private var isAdmin: Bool { authState.currentUser?.role == .admin }

    var body: some View {
        NavigationStack {
            TabView {
                // ── Tab 1: Classifica ─────────────────────────────────
                ClassificaLiveView(viewModel: viewModel)
                    .tabItem { Label("Classifica", systemImage: "list.number") }

                // ── Tab 2: Kart (Assegnazione) ────────────────────────
                KartAssignmentView(event: event, viewModel: viewModel)
                    .tabItem { Label("Kart", systemImage: "flag.2.crossed.fill") }
                    
                // ── Tab 3: Penalità ───────────────────────────────────
                KartPenaltyView(event: event, viewModel: viewModel)
                    .tabItem { Label("Penalità", systemImage: "exclamationmark.triangle.fill") }

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

                // ── Pulsante Avvia / Termina / Reset ─────────────────
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isFinished && isAdmin {
                        // Solo admin può resettare a "scheduled"
                        Button("Ripristina") {
                            pendingStatus = "scheduled"
                            showStatusConfirm = true
                        }
                        .foregroundColor(.orange)
                        .font(.system(size: 13, weight: .bold))
                    } else if !isFinished {
                        Button(isStarted ? "Termina" : "Avvia") {
                            pendingStatus = isStarted ? "finished" : "started"
                            showStatusConfirm = true
                        }
                        .foregroundColor(isStarted ? .red : .green)
                        .font(.system(size: 13, weight: .bold))
                    }
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: $showStatusConfirm, titleVisibility: .visible) {
            Button(confirmButtonLabel, role: pendingStatus == "finished" ? .destructive : nil) {
                guard let s = pendingStatus else { return }
                Task { try? await viewModel.updateEventStatus(s) }
            }
            Button("Annulla", role: .cancel) { }
        }
    }

    private var confirmTitle: String {
        switch pendingStatus {
        case "started":   return "Avviare la gara?"
        case "finished":  return "Terminare la gara?"
        case "scheduled": return "Ripristinare lo stato a 'Programmata'?"
        default:          return "Conferma"
        }
    }

    private var confirmButtonLabel: String {
        switch pendingStatus {
        case "started":   return "Avvia Gara"
        case "finished":  return "Termina Gara"
        case "scheduled": return "Ripristina"
        default:          return "Conferma"
        }
    }
}
