import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var appEnv: AppEnvironment

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                // ── Cambia Password ──────────────────────────────────────
                NavigationLink {
                    ChangePasswordView()
                        .environmentObject(authState)
                } label: {
                    HStack {
                        Image(systemName: "lock.rotation")
                            .font(.title3)
                        Text("Cambia password")
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
                .padding(.horizontal, 30)

                // ── Area Admin ───────────────────────────────────────────
                if authState.currentUser?.role.canManageUsers == true {
                    NavigationLink {
                        AdminUsersView(server: appEnv.server(token: authState.currentToken ?? ""))
                            .environmentObject(authState)
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .font(.title3)
                            Text("Gestisci Utenti")
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
                    .padding(.horizontal, 30)

                    NavigationLink {
                        AdminKartodromoView(server: appEnv.server(token: authState.currentToken ?? ""))
                            .environmentObject(authState)
                    } label: {
                        HStack {
                            Image(systemName: "flag.checkered.2.crossed")
                                .font(.title3)
                            Text("Circuiti")
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
                    .padding(.horizontal, 30)
                }

                // ── Logout ───────────────────────────────────────────────
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
                .padding(.horizontal, 30)

                Spacer()
            }
        }
        .navigationTitle("Impostazioni")
        .navigationBarTitleDisplayMode(.inline)
    }
}
