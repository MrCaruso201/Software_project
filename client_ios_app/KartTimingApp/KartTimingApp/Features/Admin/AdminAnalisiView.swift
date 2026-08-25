import SwiftUI

// MARK: - AdminAnalisiView
// Schermata Analisi dedicata agli admin/race_director.
// Mostra una barra di ricerca utenti (per username o email) e,
// selezionando un utente, ne visualizza l'analisi completa in sola lettura.

struct AdminAnalisiView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState

    @State private var searchText: String = ""
    @State private var allUsers: [AdminUser] = []       // lista completa (caricata una volta)
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var selectedUser: AdminUser? = nil

    /// Solo piloti (ruolo "user"), filtrati in base alla searchText (filtro lato client, istantaneo)
    private var filteredUsers: [AdminUser] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        let pilots = allUsers.filter { $0.role == "user" }
        guard !q.isEmpty else { return pilots }
        return pilots.filter {
            $0.username.lowercased().contains(q) ||
            $0.email.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Barra di ricerca ───────────────────────────────────────
                    searchBar
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.kartPanel)

                    // ── Contenuto ──────────────────────────────────────────────
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(.kartAccent)
                            .scaleEffect(1.3)
                        Spacer()
                    } else if let err = errorMessage {
                        Spacer()
                        errorState(err)
                        Spacer()
                    } else if filteredUsers.isEmpty && !searchText.isEmpty {
                        Spacer()
                        noResultsState
                        Spacer()
                    } else {
                        userList
                    }
                }
            }
            .navigationTitle("Analisi Utente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: Binding(
                get: { selectedUser != nil },
                set: { if !$0 { selectedUser = nil } }
            )) {
                if let user = selectedUser {
                    UserAnalisiDetailView(server: server, targetUser: user)
                        .environmentObject(authState)
                }
            }
            .onAppear {
                if allUsers.isEmpty { Task { await loadAllUsers() } }
            }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(searchText.isEmpty ? .kartDim : .kartAccent)

            TextField("", text: $searchText,
                      prompt: Text("Cerca per username o email...")
                          .foregroundColor(.kartDim))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.kartDim)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(searchText.isEmpty ? Color.white.opacity(0.06) : Color.kartAccent.opacity(0.4),
                        lineWidth: 1)
        )
    }

    // MARK: - User list

    private var userList: some View {
        ScrollView {
            // Contatore risultati
            HStack {
                Text(searchText.isEmpty
                     ? "\(allUsers.count) utenti"
                     : "\(filteredUsers.count) risultati per \"\(searchText)\"")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.kartDim)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)

            LazyVStack(spacing: 10) {
                ForEach(filteredUsers) { user in
                    userRow(user)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 30)
        }
    }

    private func userRow(_ user: AdminUser) -> some View {
        Button {
            selectedUser = user
        } label: {
            HStack(spacing: 12) {
                // Avatar iniziale
                ZStack {
                    Circle()
                        .fill(roleColor(user.role).opacity(0.18))
                        .frame(width: 42, height: 42)
                    Text(String(user.username.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(roleColor(user.role))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.username)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(user.email)
                        .font(.system(size: 12))
                        .foregroundColor(.kartDim)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(roleLabel(user.role))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(roleColor(user.role))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(roleColor(user.role).opacity(0.12))
                        .cornerRadius(6)

                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.kartAccent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.kartPanel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty / Error states

    private var emptySearchPrompt: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.kartAccent.opacity(0.08))
                    .frame(width: 90, height: 90)
                Image(systemName: "person.2.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundColor(.kartAccent.opacity(0.6))
            }
            Text("Cerca un pilota")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white.opacity(0.85))
            Text("Digita lo username o l'email di un\nutente per visualizzarne l'analisi.")
                .font(.system(size: 13))
                .foregroundColor(.kartDim)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Spacer()
        }
        .padding(32)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.slash")
                .font(.system(size: 40))
                .foregroundColor(.kartDim.opacity(0.5))
            Text("Nessun utente trovato")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.kartDim)
            Text("Prova con un altro username o email")
                .font(.system(size: 12))
                .foregroundColor(.kartDim.opacity(0.6))
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.kartRed.opacity(0.7))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.kartDim)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - Logic

    @MainActor
    private func loadAllUsers() async {
        guard let token = authState.currentToken else { return }
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await AuthService.fetchUsers(query: "", token: token)
            allUsers = fetched.sorted { $0.username.lowercased() < $1.username.lowercased() }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func roleColor(_ role: String) -> Color {
        switch role {
        case "admin":         return .orange
        case "race_director": return .cyan
        case "viewer":        return .green
        default:              return .gray
        }
    }

    private func roleLabel(_ role: String) -> String {
        switch role {
        case "admin":         return "Admin"
        case "race_director": return "Race Director"
        case "viewer":        return "Spettatore"
        default:              return "Utente"
        }
    }
}

// MARK: - UserAnalisiDetailView
// Wrapper che carica e mostra l'AnalisiView di un utente specifico (sola lettura).

struct UserAnalisiDetailView: View {
    let server: DiscoveredServer
    let targetUser: AdminUser
    @EnvironmentObject var authState: AuthState

    @StateObject private var viewModel = AnalisiViewModel()
    @State private var selectedSegment: Int = 0

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView().tint(.kartAccent).scaleEffect(1.3)
                    Text("Caricamento analisi...")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.kartDim)
                }
            } else {
                VStack(spacing: 0) {
                    segmentBar
                    pageContent
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(targetUser.username)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text(targetUser.email)
                        .font(.system(size: 10))
                        .foregroundColor(.kartDim)
                }
            }
        }
        .onAppear {
            viewModel.fetchAll(
                serverURL: server.httpURL,
                token: authState.currentToken,
                forUserId: targetUser.id
            )
        }
    }

    // MARK: - Segment bar

    private var segmentBar: some View {
        let labels = ["Panoramica", "Storico", "Circuiti"]
        return HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedSegment = i
                    }
                } label: {
                    VStack(spacing: 5) {
                        Text(label)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(selectedSegment == i ? .kartAccent : .kartDim)
                            .padding(.top, 10)
                        Rectangle()
                            .fill(selectedSegment == i ? Color.kartAccent : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.kartPanel)
    }

    @ViewBuilder
    private var pageContent: some View {
        TabView(selection: $selectedSegment) {
            panoramicaContent.tag(0)
            storicoContent.tag(1)
            circuitiContent.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.25), value: selectedSegment)
    }

    // MARK: - Panoramica

    private var panoramicaContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                Spacer(minLength: 30)
            }
            .padding(16)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text("RIEPILOGO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 9))
                    Text("SOLA LETTURA")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.kartDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.05))
                .cornerRadius(6)
            }
            .padding(14)
            .background(Color.kartAccent.opacity(0.08))

            let stats: [(String, String, String)] = [
                ("flag.fill",          "\(viewModel.totalPastRaces)",                          "Gare disputate"),
                ("mappin.and.ellipse", "\(viewModel.totalCircuitsVisited)",                    "Circuiti visitati"),
                ("trophy.fill",        viewModel.bestOfficialPosition.map { "\($0)°" } ?? "—", "Miglior posizione"),
                ("calendar.badge.checkmark", "\(viewModel.upcomingConfirmedEvents.count)",     "Prossime gare"),
            ]

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    statCell(icon: stat.0, value: stat.1, label: stat.2)
                }
            }
            .background(Color.white.opacity(0.04))
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.kartAccent)
            Text(value)
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.kartDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.kartPanel)
    }


    // MARK: - Storico

    private var storicoContent: some View {
        Group {
            if viewModel.pastConfirmedEvents.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "flag.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.kartDim.opacity(0.4))
                    Text("Nessuna gara disputata")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.kartDim)
                    Text("Questo utente non ha ancora gare passate confermate")
                        .font(.system(size: 12))
                        .foregroundColor(.kartDim.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.pastConfirmedEvents, id: \.event.id) { item in
                            PastEventCard(
                                event: item.event,
                                result: viewModel.result(for: item.event.id),
                                server: server,
                                viewModel: viewModel
                            )
                            .environmentObject(authState)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // MARK: - Circuiti (sola lettura, senza pulsante aggiungi)

    private var circuitiContent: some View {
        Group {
            if viewModel.circuitStats.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "map.slash")
                        .font(.system(size: 44))
                        .foregroundColor(.kartDim.opacity(0.4))
                    Text("Nessun circuito visitato")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.kartDim)
                    Text("I dati appariranno dopo le prime gare")
                        .font(.system(size: 12))
                        .foregroundColor(.kartDim.opacity(0.6))
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .padding(32)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.circuitStats) { stat in
                            CircuitCard(stat: stat)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
    }
}
