import SwiftUI

struct AdminUsersView: View {
    @EnvironmentObject var authState: AuthState

    @State private var searchText: String = ""
    @State private var users: [AdminUser] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    // Debounce timer per non sparare richieste ad ogni carattere
    @State private var searchTask: Task<Void, Never>? = nil

    private let availableRoles: [(label: String, value: String)] = [
        ("Spettatore",       "viewer"),
        ("Direttore di Gara", "race_director"),
        ("Admin",            "admin"),
    ]

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Barra di ricerca ──────────────────────────────────────
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.kartDim)
                    TextField("Cerca per nome o email…", text: $searchText)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchText) { _, _ in
                            triggerSearch()
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.kartDim)
                        }
                    }
                }
                .padding(12)
                .background(Color.kartPanel)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ── Feedback messaggi ─────────────────────────────────────
                if let err = errorMessage {
                    feedbackBanner(text: err, isError: true)
                } else if let ok = successMessage {
                    feedbackBanner(text: ok, isError: false)
                }

                // ── Lista utenti ──────────────────────────────────────────
                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                    Spacer()
                } else if users.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.kartDim)
                        Text(searchText.isEmpty ? "Nessun utente nel sistema" : "Nessun risultato per «\(searchText)»")
                            .font(.subheadline)
                            .foregroundColor(.kartDim)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach($users) { $user in
                                UserCard(
                                    user: $user,
                                    availableRoles: availableRoles,
                                    onRoleChange: { newRole in
                                        changeRole(user: user, newRole: newRole)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .navigationTitle("Gestisci Utenti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { triggerSearch() }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func feedbackBanner(text: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            Text(text)
                .font(.footnote.weight(.medium))
        }
        .foregroundColor(isError ? .red : .green)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((isError ? Color.red : Color.green).opacity(0.12))
        .cornerRadius(10)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.opacity)
    }

    // MARK: - Logic

    private func triggerSearch() {
        searchTask?.cancel()
        searchTask = Task {
            // Debounce: aspetta 300 ms prima di fare la richiesta
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await loadUsers()
        }
    }

    @MainActor
    private func loadUsers() async {
        guard let token = authState.currentToken else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil

        do {
            users = try await AuthService.fetchUsers(query: searchText, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func changeRole(user: AdminUser, newRole: String) {
        guard let token = authState.currentToken else { return }
        Task {
            do {
                try await AuthService.updateUserRole(userId: user.id, role: newRole, token: token)
                // Aggiorna localmente il ruolo per riflettere la modifica
                if let idx = users.firstIndex(where: { $0.id == user.id }) {
                    await MainActor.run { users[idx].role = newRole }
                }
                await MainActor.run {
                    successMessage = "Ruolo di \(user.username) aggiornato a \"\(newRole)\""
                    // Nascondi il messaggio dopo 3 secondi
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        successMessage = nil
                    }
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Card singolo utente
// ---------------------------------------------------------------------------

private struct UserCard: View {
    @Binding var user: AdminUser
    let availableRoles: [(label: String, value: String)]
    let onRoleChange: (String) -> Void

    @State private var selectedRole: String = ""

    private var roleLabel: String {
        availableRoles.first(where: { $0.value == user.role })?.label ?? user.role
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Riga superiore: icona + username + email
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.2))
                        .frame(width: 42, height: 42)
                    Text(String(user.username.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(roleColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(user.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text(user.email)
                        .font(.system(size: 12))
                        .foregroundColor(.kartDim)
                }

                Spacer()

                // Badge ruolo corrente
                Text(roleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(roleColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(roleColor.opacity(0.15))
                    .cornerRadius(8)
            }

            // Picker ruolo
            HStack {
                Text("Ruolo:")
                    .font(.footnote)
                    .foregroundColor(.kartDim)

                Picker("Ruolo", selection: $selectedRole) {
                    ForEach(availableRoles, id: \.value) { r in
                        Text(r.label).tag(r.value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedRole) { oldVal, newVal in
                    if newVal != oldVal && newVal != user.role {
                        onRoleChange(newVal)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear { selectedRole = user.role }
        .onChange(of: user.role) { _, newRole in selectedRole = newRole }
    }

    private var roleColor: Color {
        switch user.role {
        case "admin":        return .orange
        case "race_director": return .cyan
        default:             return .gray
        }
    }
}
