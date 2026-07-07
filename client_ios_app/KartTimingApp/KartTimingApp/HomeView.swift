import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var appEnv: AppEnvironment
    @State private var selectedTab: HomeTab = .home

    var body: some View {
        if authState.isGuestSession {
            // Per il guest, nessuna barra inferiore di navigazione, solo la TimingView come prima
            NavigationStack {
                TimingView(server: appEnv.server(token: authState.currentToken ?? ""))
            }
        } else {
            // Per utenti loggati, barra di navigazione standard di iOS
            TabView(selection: $selectedTab) {
                
                NavigationStack {
                    homePlaceholder
                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(HomeTab.home)
                
                NavigationStack {
                    EventiView(server: appEnv.server(token: authState.currentToken ?? ""))
                }
                .tabItem {
                    Label("Eventi", systemImage: "calendar")
                }
                .tag(HomeTab.eventi)
                
                NavigationStack {
                    TimingView(server: appEnv.server(token: authState.currentToken ?? ""))
                }
                .tabItem {
                    Label("Timing", systemImage: "stopwatch.fill")
                }
                .tag(HomeTab.timing)
                
                NavigationStack {
                    Text("Analisi in costruzione")
                        .foregroundColor(.kartDim)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.kartBG)
                        .navigationTitle("Analisi")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .tabItem {
                    Label("Analisi", systemImage: "trophy.fill")
                }
                .tag(HomeTab.analisi)
                
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Impostazioni", systemImage: "gearshape.fill")
                }
                .tag(HomeTab.settings)
                
                if authState.currentUser?.role.canManageUsers == true {
                    NavigationStack {
                        AdminUsersView(server: appEnv.server(token: authState.currentToken ?? ""))
                    }
                    .tabItem {
                        Label("Gestisci Utenti", systemImage: "person.2.fill")
                    }
                    .tag(HomeTab.admin)

                    NavigationStack {
                        AdminKartodromoView(server: appEnv.server(token: authState.currentToken ?? ""))
                            .environmentObject(authState)
                    }
                    .tabItem {
                        Label("Circuiti", systemImage: "flag.checkered.2.crossed")
                    }
                    .tag(HomeTab.circuiti)
                }
            }
            // Colore dell'icona selezionata nella TabBar
            .tint(Color(red: 1.0, green: 0.82, blue: 0.0))
        }
    }

    private var homePlaceholder: some View {
        VStack {
            Text("Area in costruzione")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.kartDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.kartBG)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum HomeTab {
    case home
    case eventi
    case timing
    case analisi
    case settings
    case admin
    case circuiti
}

