import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var appEnv: AppEnvironment
    @State private var selectedTab: HomeTab = .home

    var body: some View {
        if authState.isGuestSession {
            // Per il guest, nessuna barra inferiore di navigazione, solo la TimingView
            NavigationStack {
                TimingView(server: appEnv.server(token: authState.currentToken ?? ""))
            }
        } else {
            // Per utenti loggati, barra di navigazione standard di iOS
            TabView(selection: $selectedTab) {

                NavigationStack {
                    UserHomeView(server: appEnv.server(token: authState.currentToken ?? ""))
                }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(HomeTab.home)

                NavigationStack {
                    EventiView(server: appEnv.server(token: authState.currentToken ?? ""))
                }
                .tabItem { Label("Eventi", systemImage: "calendar") }
                .tag(HomeTab.eventi)

                NavigationStack {
                    TimingView(server: appEnv.server(token: authState.currentToken ?? ""))
                }
                .tabItem { Label("Timing", systemImage: "stopwatch.fill") }
                .tag(HomeTab.timing)

                NavigationStack {
                    AnalisiView(server: appEnv.server(token: authState.currentToken ?? ""))
                }
                .tabItem { Label("Analisi", systemImage: "trophy.fill") }
                .tag(HomeTab.analisi)

                NavigationStack {
                    SettingsView()
                }
                .tabItem { Label("Impostazioni", systemImage: "gearshape.fill") }
                .tag(HomeTab.settings)

                // Le view di amministrazione sono state spostate dentro SettingsView per evitare il tab "Altro" (>5 tabs)
            }
            .tint(Color(red: 1.0, green: 0.82, blue: 0.0))
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenEventDetail"))) { notif in
                self.selectedTab = .eventi
                if let eventId = notif.userInfo?["eventId"] as? Int {
                    appEnv.pendingEventIdToOpen = eventId
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenLiveTiming"))) { _ in
                self.selectedTab = .timing
            }
        }
    }


}

enum HomeTab {
    case home
    case eventi
    case timing
    case analisi
    case settings
}
