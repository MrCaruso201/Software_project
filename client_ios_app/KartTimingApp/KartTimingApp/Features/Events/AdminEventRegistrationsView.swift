import SwiftUI

struct AdminEventRegistrationsView: View {
    let server: DiscoveredServer
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent
    
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    
    // Vista individuale (gare non a squadre)
    @State private var registrations: [EventRegistrationWithUserResponse] = []
    // Vista team (gare a squadre)
    @State private var teams: [TeamRegistrationResponse] = []
    
    @State private var isLoading = true
    
    private var isTeamEvent: Bool { event.isTeamEvent }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                if isLoading {
                    ProgressView().tint(.kartAccent).scaleEffect(1.3)
                } else if isTeamEvent {
                    teamContent
                } else {
                    individualContent
                }
            }
            .navigationTitle("Iscrizioni: \(event.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
            .onAppear {
                loadRegistrations()
            }
        }
    }
    
    // MARK: - Individual View
    
    private var individualContent: some View {
        Group {
            if registrations.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(registrations) { reg in
                        individualRow(reg)
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
    
    // MARK: - Team View
    
    private var teamContent: some View {
        Group {
            if teams.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(teams) { team in
                            teamCard(team)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    private func teamCard(_ team: TeamRegistrationResponse) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header team ─────────────────────────────────
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.teamName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("\(team.members.count) partecipanti")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.kartDim)
                }
                
                Spacer()
                
                // Badge status
                Text(team.overallStatus == "confirmed" ? "Confermata" : "Attesa Pag.")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(team.overallStatus == "confirmed"
                                ? Color.green.opacity(0.2)
                                : Color.orange.opacity(0.2))
                    .foregroundColor(team.overallStatus == "confirmed" ? .green : .orange)
                    .cornerRadius(5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.kartPanel)
            
            Divider().background(Color.white.opacity(0.08))
            
            // ── Lista membri ─────────────────────────────────
            VStack(spacing: 0) {
                ForEach(team.members) { member in
                    HStack(spacing: 10) {
                        // Foto profilo (o person.fill se non disponibile)
                        teamMemberAvatar(member: member)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            if let name = member.username, !name.isEmpty {
                                Text(name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            if let email = member.email {
                                Text(email)
                                    .font(.system(size: 11))
                                    .foregroundColor(.kartDim)
                            }
                        }
                        
                        Spacer()
                        
                        if member.isTeamLeader {
                            Text("LEADER")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.kartAccent.opacity(0.2))
                                .foregroundColor(.kartAccent)
                                .cornerRadius(3)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    
                    if member.id != team.members.last?.id {
                        Divider()
                            .background(Color.white.opacity(0.05))
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Color.kartPanel.opacity(0.6))
            
            Divider().background(Color.white.opacity(0.08))
            
            // ── Azioni admin ───────────────────────────────────────
            HStack(spacing: 10) {
                if team.overallStatus != "confirmed" {
                    Button {
                        confirmTeam(teamId: team.teamId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Conferma Pag.")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(7)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button {
                    deleteTeam(teamId: team.teamId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Rimuovi Team")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.kartRed)
                    .foregroundColor(.white)
                    .cornerRadius(7)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.kartPanel.opacity(0.4))
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    team.overallStatus == "confirmed"
                        ? Color.green.opacity(0.2)
                        : Color.white.opacity(0.07),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Individual Row
    
    @ViewBuilder
    private func teamMemberAvatar(member: TeamMemberResponse) -> some View {
        if let picPath = member.profilePictureUrl,
           let base = server.httpURL.flatMap({ url -> URL? in
               var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
               c?.path = ""; c?.query = nil
               return c?.url
           }) {
            let clean = picPath.hasPrefix("/") ? String(picPath.dropFirst()) : picPath
            let url = base.appendingPathComponent(clean)
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                        .frame(width: 32, height: 32).clipShape(Circle())
                case .failure:
                    memberFallbackIcon
                default:
                    Circle().fill(Color.white.opacity(0.07))
                        .frame(width: 32, height: 32)
                        .overlay(ProgressView().scaleEffect(0.5))
                }
            }
        } else {
            memberFallbackIcon
        }
    }
    
    private var memberFallbackIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 14))
            .foregroundColor(.kartDim)
            .frame(width: 32, height: 32)
            .background(Color.white.opacity(0.06))
            .clipShape(Circle())
    }
    
    private func profileImageURL(for reg: EventRegistrationWithUserResponse) -> URL? {
        guard let picPath = reg.profilePictureUrl else { return nil }
        guard let base = server.httpURL.flatMap({ url -> URL? in
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            comps?.path = ""
            comps?.query = nil
            return comps?.url
        }) else { return nil }
        let clean = picPath.hasPrefix("/") ? String(picPath.dropFirst()) : picPath
        return base.appendingPathComponent(clean)
    }
    

    private func individualRow(_ reg: EventRegistrationWithUserResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // ── Foto profilo ──────────────────────────────────
                profileThumbnail(for: reg)
                
                // ── Nome + status ─────────────────────────────────
                VStack(alignment: .leading, spacing: 2) {
                    Text(reg.username ?? reg.email ?? "Utente")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if let email = reg.email, reg.username != nil {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundColor(.kartDim)
                    }
                }
                
                Spacer()
                
                if reg.status == "confirmed" {
                    Text("Confermata")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                } else {
                    Text("Attesa Pag.")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
            }


            HStack(spacing: 12) {
                if reg.status != "confirmed", let userId = reg.userId {
                    Button {
                        confirmIndividual(userId: userId)
                    } label: {
                        Text("Conferma Pagamento")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                if let userId = reg.userId {
                    Button {
                        deleteIndividual(userId: userId)
                    } label: {
                        Text("Rimuovi")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.kartRed)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.kartPanel)
    }
    
    @ViewBuilder
    private func profileThumbnail(for reg: EventRegistrationWithUserResponse) -> some View {
        if let url = profileImageURL(for: reg) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                case .failure:
                    fallbackAvatar
                default:
                    Circle()
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 40, height: 40)
                        .overlay(ProgressView().scaleEffect(0.6))
                }
            }
        } else {
            fallbackAvatar
        }
    }
    
    private var fallbackAvatar: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 40, height: 40)
            .foregroundColor(.kartDim)
    }
    
    // MARK: - Empty View
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: isTeamEvent ? "person.3" : "person")
                .font(.system(size: 40))
                .foregroundColor(.kartDim)
            Text(isTeamEvent ? "Nessuna squadra iscritta" : "Nessun iscritto")
                .foregroundColor(.kartDim)
                .padding(.top, 4)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadRegistrations() {
        guard let token = authState.currentToken else { return }
        isLoading = true
        
        if isTeamEvent {
            viewModel.fetchTeamRegistrations(serverURL: server.httpURL, eventId: event.id, token: token) { loadedTeams in
                self.isLoading = false
                self.teams = loadedTeams ?? []
            }
        } else {
            viewModel.fetchEventRegistrations(serverURL: server.httpURL, eventId: event.id, token: token) { loadedRegs in
                self.isLoading = false
                self.registrations = loadedRegs ?? []
            }
        }
    }
    
    // MARK: - Actions (Team)
    
    private func confirmTeam(teamId: String) {
        guard let token = authState.currentToken else { return }
        viewModel.adminConfirmTeamRegistration(serverURL: server.httpURL, eventId: event.id, teamId: teamId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    private func deleteTeam(teamId: String) {
        guard let token = authState.currentToken else { return }
        viewModel.adminDeleteTeamRegistration(serverURL: server.httpURL, eventId: event.id, teamId: teamId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    // MARK: - Actions (Individual)
    
    private func confirmIndividual(userId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.confirmRegistration(serverURL: server.httpURL, eventId: event.id, userId: userId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    private func deleteIndividual(userId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.adminDeleteRegistration(serverURL: server.httpURL, eventId: event.id, userId: userId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
}
