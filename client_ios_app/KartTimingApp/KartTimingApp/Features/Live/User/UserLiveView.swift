import SwiftUI

/// Vista Live per i piloti/componenti del team con TabView nativa iOS.
struct UserLiveView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel

    @Environment(\.dismiss) private var dismiss

    @State private var navigateToPilot: Bool = false

    private var isStarted: Bool { event.status == "started" }
    private var kartNumber: Int? { viewModel.myKart.kartNumber }

    var body: some View {
        NavigationStack {
            TabView {
                // ── Tab 1: Classifica ─────────────────────────────────
                ClassificaLiveView(viewModel: viewModel)
                    .tabItem { Label("Classifica", systemImage: "list.number") }
                
                // ── Tab 2: Team View ──────────────────────────────────
                TeamLiveView(viewModel: viewModel)
                    .tabItem { Label("Team View", systemImage: "person.3.fill") }
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
                // ── Pulsante Pilot View ────────────────────────────────
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
            .navigationDestination(isPresented: $navigateToPilot) {
                PilotLiveView(viewModel: viewModel)
            }
        }
    }
}
