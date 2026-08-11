import SwiftUI

/// Vista Live per i piloti/componenti del team.
/// Permette di switchare liberamente tra Team View e Pilot View.
struct UserLiveView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    let dismiss: DismissAction

    @State private var selectedTab: UserLiveTab = .team

    var body: some View {
        VStack(spacing: 0) {
            // ── Custom Navigation Bar ───────────────────────────────────────
            userNavBar

            // ── Tab Content ─────────────────────────────────────────────────
            TabView(selection: $selectedTab) {
                TeamLiveView(viewModel: viewModel)
                    .tag(UserLiveTab.team)

                PilotLiveView(viewModel: viewModel)
                    .tag(UserLiveTab.pilot)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.2), value: selectedTab)

            // ── Bottom Tab Bar ──────────────────────────────────────────────
            userTabBar
        }
        .background(Color.kartBG)
    }

    // MARK: - Navigation Bar

    private var userNavBar: some View {
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
                    Text(event.status == "started" ? "LIVE" : "NON INIZIATA")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(event.status == "started" ? .red : .kartDim)
                }
                Text(event.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Spacer()

            // Kart number badge
            if let kart = viewModel.myKart.kartNumber {
                VStack(spacing: 1) {
                    Text("#\(kart)")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    Text("KART")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartDim)
                }
                .frame(width: 52)
            } else {
                Color.clear.frame(width: 52)
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

    private var userTabBar: some View {
        HStack(spacing: 0) {
            ForEach(UserLiveTab.allCases) { tab in
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

enum UserLiveTab: String, CaseIterable, Identifiable {
    case team, pilot
    var id: String { rawValue }
    var label: String {
        switch self {
        case .team:  return "Team View"
        case .pilot: return "Pilot View"
        }
    }
    var icon: String {
        switch self {
        case .team:  return "person.3.fill"
        case .pilot: return "person.fill"
        }
    }
}
