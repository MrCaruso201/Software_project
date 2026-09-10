import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var appEnv: AppEnvironment
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    themePicker

                    // ── Informazioni Personali ───────────────────────────────
                    NavigationLink {
                        EditProfileView()
                            .environmentObject(authState)
                            .environmentObject(appEnv)
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.title3)
                            Text("Informazioni Personali")
                                .font(.title2.weight(.bold))
                        }
                        .foregroundColor(.kartForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.kartPanel)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 30)

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
                        .foregroundColor(.kartForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.kartPanel)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
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
                            .foregroundColor(.kartForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.kartPanel)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
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
                            .foregroundColor(.kartForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.kartPanel)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
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
                        .foregroundColor(.kartRed)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.kartRed.opacity(0.08))
                        .background(Color.kartPanel)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.kartRed.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 30)

                }
                .padding(.vertical, 24)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var themePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tema", systemImage: "circle.lefthalf.filled")
                .font(.headline)
                .foregroundColor(.kartForeground)

            Picker("Tema", selection: $theme) {
                ForEach(AppTheme.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text("Sistema segue l’aspetto impostato sul telefono.")
                .font(.footnote)
                .foregroundColor(.kartDim)
        }
        .padding(18)
        .background(Color.kartPanel)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
        )
        .padding(.horizontal, 30)
    }

}
