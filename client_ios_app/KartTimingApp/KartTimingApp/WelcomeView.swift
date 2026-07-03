import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authState: AuthState
    @State private var navigateToTiming = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Sfondo
                Color.kartBG.ignoresSafeArea()

                VStack(spacing: 24) {

                    Spacer()

                    Text("Race Manager")
                        .font(.system(size: 40, weight: .heavy, design: .default))
                        .foregroundColor(.white)
                        .padding(.bottom, 40)

                    // 1. Profilo / Logout
                    VStack(spacing: 8) {
                        Text("Loggato come \(authState.currentUser?.role.displayName ?? "Utente")")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.kartDim)

                        Button {
                            authState.logout()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.title3)
                                Text("Logout")
                                    .font(.title2.weight(.bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.kartPanel)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                    }

                    // 2. Pulsante per Live Timing (loggato)
                    NavigationLink(value: WelcomeDestination.liveTiming) {
                        HStack {
                            Image(systemName: "stopwatch.fill")
                                .font(.title3)
                            Text("Live Timing")
                                .font(.title2.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.kartPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)

                    // 3. Pulsante "Gestisci Utenti" — solo admin
                    if authState.currentUser?.role.canManageUsers == true {
                        NavigationLink(value: WelcomeDestination.adminUsers) {
                            HStack {
                                Image(systemName: "person.badge.gear")
                                    .font(.title3)
                                Text("Gestisci Utenti")
                                    .font(.title2.weight(.bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [Color.orange.opacity(0.7), Color.orange.opacity(0.4)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .padding(.horizontal, 30)
            }
            .onAppear {
                // Se l'utente ha fatto login come guest, vai direttamente al TimingView
                if authState.isGuestSession {
                    navigateToTiming = true
                }
            }
            // Necessario per colorare bene la barra di navigazione
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $navigateToTiming) {
                TimingView(server: DiscoveredServer.remoteServer(token: authState.currentToken ?? ""))
            }
            .navigationDestination(for: WelcomeDestination.self) { destination in
                switch destination {
                case .liveTiming:
                    TimingView(server: DiscoveredServer.remoteServer(token: authState.currentToken ?? ""))
                case .adminUsers:
                    AdminUsersView()
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Destinazioni NavigationStack per WelcomeView
// ---------------------------------------------------------------------------

enum WelcomeDestination: Hashable {
    case liveTiming
    case adminUsers
}
