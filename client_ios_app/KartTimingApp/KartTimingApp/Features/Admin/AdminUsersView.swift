import SwiftUI

struct AdminUsersView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState

    @State private var searchText: String = ""
    @State private var users: [AdminUser] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var expandedUserId: Int? = nil

    // Debounce timer per non sparare richieste ad ogni carattere
    @State private var searchTask: Task<Void, Never>? = nil

    private let availableRoles: [(label: String, value: String)] = [
        ("Spettatore",       "viewer"),
        ("Utente", "user"),
        ("Direttore di Gara", "race_director"),
        ("Admin",            "admin"),
    ]

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header Bar (Stile Eventi) ───────────────────────────────────
                headerBar

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
                        LazyVStack(spacing: 12) {
                            ForEach($users) { $user in
                                UserCard(
                                    user: $user,
                                    availableRoles: availableRoles,
                                    currentUserId: authState.currentUser?.id,
                                    isExpanded: expandedUserId == user.id,
                                    onToggle: {
                                        if expandedUserId == user.id {
                                            expandedUserId = nil
                                        } else {
                                            expandedUserId = user.id
                                        }
                                    },
                                    onRoleChange: { newRole in
                                        changeRole(user: user, newRole: newRole)
                                    }
                                )
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
            
            // ── Feedback messaggi (in basso) ─────────────────────────────────
            VStack {
                Spacer()
                if let err = errorMessage {
                    feedbackBanner(text: err, isError: true)
                        .padding(.bottom, 20)
                } else if let ok = successMessage {
                    feedbackBanner(text: ok, isError: false)
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Utenti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Barra ricerca stile Live Timing / Eventi
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                    TextField("", text: $searchText, prompt: Text("CERCA UTENTI").foregroundColor(.black))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .disableAutocorrection(true)
                        .textInputAutocapitalization(.never)
                        .onChange(of: searchText) { _, _ in
                            triggerSearch()
                        }
                }
                .environment(\.colorScheme, .light)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.82, blue: 0.0),
                                 Color(red: 1.0, green: 0.65, blue: 0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.4), radius: 6, x: 0, y: 3)
            }
        }
        .onAppear { triggerSearch() }
    }

    // MARK: - Helper Views

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Utenti a sistema")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Text("\(users.count) trovati")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.kartDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kartPanel)
    }

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
            let fetched = try await AuthService.fetchUsers(query: searchText, token: token)
            users = fetched.sorted { u1, u2 in
                let w1 = roleWeight(u1.role)
                let w2 = roleWeight(u2.role)
                if w1 == w2 {
                    return u1.username.lowercased() < u2.username.lowercased()
                }
                return w1 < w2
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func roleWeight(_ role: String) -> Int {
        switch role {
        case "admin": return 0
        case "race_director": return 1
        case "user": return 2
        case "viewer": return 3
        default: return 4
        }
    }

    private func changeRole(user: AdminUser, newRole: String) {
        guard let token = authState.currentToken else { return }
        Task {
            do {
                try await AuthService.updateUserRole(userId: user.id, role: newRole, token: token)
                // Aggiorna localmente il ruolo per riflettere la modifica e riordina
                if let idx = users.firstIndex(where: { $0.id == user.id }) {
                    await MainActor.run { 
                        users[idx].role = newRole 
                        users.sort { u1, u2 in
                            let w1 = roleWeight(u1.role)
                            let w2 = roleWeight(u2.role)
                            if w1 == w2 {
                                return u1.username.lowercased() < u2.username.lowercased()
                            }
                            return w1 < w2
                        }
                    }
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
    let currentUserId: Int?
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRoleChange: (String) -> Void

    /// True quando la card rappresenta l'admin attualmente loggato
    private var isSelf: Bool { user.id == currentUserId }

    /// True quando la card rappresenta il superutente di sistema (username "admin"),
    /// il cui ruolo non può essere modificato da nessun altro admin.
    private var isSuperuser: Bool { user.username == "admin" }

    /// True quando la card rappresenta l'utente speciale per il solo live timing
    private var isViewerUser: Bool { user.username == "viewer" }

    /// True quando il picker deve essere bloccato
    private var isLocked: Bool { isSelf || isSuperuser || isViewerUser }

    private var lockLabel: String {
        if isSelf { return "Non modificabile (account corrente)" }
        if isViewerUser { return "Utenza usata per la sola visualizzazione" }
        return "Non modificabile (superutente di sistema)"
    }

    @State private var selectedRole: String = ""

    private var roleLabel: String {
        availableRoles.first(where: { $0.value == user.role })?.label ?? user.role
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header (Sempre visibile) ─────────────────────────
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(roleColor.opacity(0.2))
                        .frame(width: 42, height: 42)
                    Text(String(user.username.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(roleColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text(roleLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(roleColor)
                }

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.kartDim)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.kartPanel)
            
            // ── Corpo espanso ─────────────────────────────────────────
            if isExpanded {
                Divider().background(Color.white.opacity(0.1))
                
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.kartDim)
                            .font(.system(size: 12))
                        Text(user.email)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    
                    if isLocked {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                            Text(lockLabel)
                                .font(.caption)
                        }
                        .foregroundColor(.kartDim)
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        // Slider base di iOS a tutta larghezza
                        Picker("Ruolo", selection: $selectedRole) {
                            ForEach(availableRoles.filter { $0.value != "viewer" }, id: \.value) { r in
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.kartPanel.opacity(0.95))
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                onToggle()
            }
        }
        .onAppear { selectedRole = user.role }
        .onChange(of: user.role) { _, newRole in selectedRole = newRole }
    }

    private var roleColor: Color {
        roleColorFor(user.role)
    }

    private func roleColorFor(_ role: String) -> Color {
        switch role {
        case "admin":        return .orange
        case "race_director": return .cyan
        case "viewer":       return .green
        default:             return .gray
        }
    }
}
