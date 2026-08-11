import SwiftUI

/// Pannello principale Race Director: 3 tab (Classifica Live / Kart & Penalità / Messaggi)
struct DirectorLiveView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    let dismiss: DismissAction

    @State private var selectedTab: DirectorTab = .karts
    @State private var showStatusConfirm = false
    @State private var pendingStatus: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // ── Custom Navigation Bar ───────────────────────────────────────
            directorNavBar

            // ── Tab Content ─────────────────────────────────────────────────
            TabView(selection: $selectedTab) {
                ClassificaLiveView(viewModel: viewModel)
                    .tag(DirectorTab.classifica)

                KartPanelView(event: event, viewModel: viewModel)
                    .tag(DirectorTab.karts)

                MessaggiView(viewModel: viewModel)
                    .tag(DirectorTab.messaggi)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            // ── Bottom Tab Bar ──────────────────────────────────────────────
            directorTabBar
        }
        .confirmationDialog(
            pendingStatus == "started" ? "Avvia la gara?" : "Termina la gara?",
            isPresented: $showStatusConfirm,
            titleVisibility: .visible
        ) {
            Button(pendingStatus == "started" ? "Avvia Gara" : "Termina Gara",
                   role: pendingStatus == "finished" ? .destructive : nil) {
                guard let s = pendingStatus else { return }
                Task { try? await viewModel.updateEventStatus(s) }
            }
            Button("Annulla", role: .cancel) { }
        }
    }

    // MARK: - Navigation Bar

    private var directorNavBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                    Text("Chiudi")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.kartAccent)
            }

            Spacer()

            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(event.status == "started" ? 1 : 0)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(event.status == "started" ? .red : .kartDim)
                }
                Text(event.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            // Bottone Avvia / Termina
            Button(action: {
                pendingStatus = event.status == "started" ? "finished" : "started"
                showStatusConfirm = true
            }) {
                Text(event.status == "started" ? "Termina" : "Avvia")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(event.status == "started" ? .red : .green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        (event.status == "started" ? Color.red : Color.green).opacity(0.15)
                    )
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kartPanel)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.08))
        }
    }

    // MARK: - Tab Bar

    private var directorTabBar: some View {
        HStack(spacing: 0) {
            ForEach(DirectorTab.allCases) { tab in
                Button(action: { withAnimation { selectedTab = tab } }) {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 20))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(selectedTab == tab ? .kartAccent : .kartDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .overlay(alignment: .top) {
                        if selectedTab == tab {
                            Rectangle()
                                .fill(Color.kartAccent)
                                .frame(height: 2)
                                .cornerRadius(1)
                        }
                    }
                }
            }
        }
        .background(Color.kartPanel)
        .overlay(alignment: .top) {
            Divider().background(Color.white.opacity(0.08))
        }
    }
}

enum DirectorTab: String, CaseIterable, Identifiable {
    case classifica, karts, messaggi
    var id: String { rawValue }
    var label: String {
        switch self {
        case .classifica: return "Classifica"
        case .karts:      return "Kart & Penalità"
        case .messaggi:   return "Messaggi"
        }
    }
    var icon: String {
        switch self {
        case .classifica: return "list.number"
        case .karts:      return "flag.2.crossed.fill"
        case .messaggi:   return "bubble.left.and.bubble.right.fill"
        }
    }
}
