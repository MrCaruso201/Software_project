import SwiftUI
import UniformTypeIdentifiers

struct AdminEventRegistrationsView: View {
    let server: DiscoveredServer
    @ObservedObject var viewModel: EventsViewModel
    let event: RaceEvent
    var showAsSheet: Bool = false

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    
    // Vista individuale (gare non a squadre)
    @State private var registrations: [EventRegistrationWithUserResponse] = []
    // Vista team (gare a squadre)
    @State private var teams: [TeamRegistrationResponse] = []
    @State private var unassignedRegistrations: [EventRegistrationWithUserResponse] = []
    
    private var enrolledTeams: [TeamRegistrationResponse] {
        teams.filter { $0.overallStatus != "waitlist" }
    }
    
    private var waitlistTeams: [TeamRegistrationResponse] {
        teams.filter { $0.overallStatus == "waitlist" }
    }
    
    @State private var isLoading = true
    
    @State private var showAddRegistrationSheet = false
    @State private var showReleaseFormSheet = false
    @State private var teamToEdit: TeamRegistrationResponse? = nil
    @State private var registrationToAssign: EventRegistrationWithUserResponse? = nil

    // CSV Import
    @State private var showCSVImporter     = false
    @State private var isUploadingCSV      = false
    @State private var csvImportAlert      = false
    @State private var csvImportMessage    = ""
    
    private var isTeamEvent: Bool { event.isTeamEvent }
    
    var body: some View {
        if showAsSheet {
            NavigationStack { navigationContent }
        } else {
            navigationContent
        }
    }

    @ViewBuilder
    private var navigationContent: some View {
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
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Aggiungi iscrizione
                Button(action: { showAddRegistrationSheet = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundColor(.kartAccent)
            }
            if showAsSheet {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
        }
        .onAppear {
            loadRegistrations()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RefreshRegistrations"))) { _ in
            loadRegistrations()
        }
        .sheet(isPresented: $showAddRegistrationSheet, onDismiss: {
            loadRegistrations()
        }) {
            AdminAddRegistrationSheetView(
                server: server,
                viewModel: viewModel,
                event: event,
                isTeamEvent: isTeamEvent
            )
        }
        .sheet(item: $teamToEdit, onDismiss: {
            loadRegistrations()
        }) { team in
            let mockReg = EventRegistrationResponse(
                id: 0,
                userId: nil,
                eventId: event.id,
                status: team.overallStatus,
                teamName: team.teamName,
                teamId: team.teamId,
                isTeamLeader: true,
                memberEmail: nil,
                createdAt: "",
                hasSignedRelease: nil
            )
            EventTeamEditSheetView(
                server: server,
                viewModel: viewModel,
                event: event,
                registration: mockReg,
                isAdmin: true
            )
        }
        .sheet(item: $registrationToAssign, onDismiss: {
            loadRegistrations()
        }) { reg in
            AdminTeamSelectionSheet(
                server: server,
                viewModel: viewModel,
                event: event,
                registration: reg,
                availableTeams: teams.filter { team in
                    let maxMembers = event.maxPeoplePerGroup ?? 1
                    return team.acceptsExtraPilots && team.members.count < maxMembers
                }
            )
        }
        .sheet(isPresented: $showReleaseFormSheet, onDismiss: {
            loadRegistrations()
        }) {
            AdminReleaseFormSheetView(
                server: server,
                viewModel: viewModel,
                event: event
            )
            .environmentObject(authState)
        }
        // ── CSV file picker ──────────────────────────────────────────
        .fileImporter(
            isPresented: $showCSVImporter,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                uploadCSV(url: url)
            case .failure:
                csvImportMessage = "Impossibile aprire il file. Riprova."
                csvImportAlert = true
            }
        }
        .alert("Importazione classifica", isPresented: $csvImportAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(csvImportMessage)
        }
    }

    
    // MARK: - Individual View
    
    private var individualContent: some View {
        Group {
            if registrations.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(registrations) { reg in
                            individualRow(reg)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
    }
    
    // MARK: - Team View
    
    private var teamContent: some View {
        Group {
            if teams.isEmpty && unassignedRegistrations.isEmpty {
                emptyView
            } else {
                ScrollView {
                    LazyVStack(spacing: 20) {
                        if !unassignedRegistrations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("PILOTI DA ACCORPARE")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.kartAccent)
                                    .padding(.horizontal, 16)
                                    
                                ForEach(unassignedRegistrations) { reg in
                                    individualRow(reg)
                                }
                            }
                            .padding(.top, 10)
                            
                            Divider().background(Color.kartBorder(opacity: 0.1))
                        }
                        
                        if !waitlistTeams.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SQUADRE IN LISTA D'ATTESA (ISCRITTE TARDI)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.purple)
                                    .padding(.horizontal, 16)
                                    
                                ForEach(waitlistTeams) { team in
                                    teamCard(team)
                                }
                            }
                            .padding(.top, 10)
                            
                            Divider().background(Color.kartBorder(opacity: 0.1))
                        }
                        
                        if !enrolledTeams.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SQUADRE ISCRITTE")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.kartForeground)
                                    .padding(.horizontal, 16)
                                    
                                ForEach(enrolledTeams) { team in
                                    teamCard(team)
                                }
                            }
                            .padding(.top, 10)
                        }
                    }
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
                        .foregroundColor(.kartForeground)
                    
                    HStack(spacing: 6) {
                        Text("\(team.members.count) partecipanti")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.kartDim)
                            
                        if let maxP = event.maxPeoplePerGroup {
                            if team.members.count < maxP && team.acceptsExtraPilots {
                                Text("• ACCETTA EXTRA")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.kartSuccess)
                            }
                        }
                    }
                }
                
                Spacer()
                
                // Badge status
                if team.overallStatus == "waitlist" {
                    Text("Lista d'Attesa")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(5)
                } else {
                    Text(team.overallStatus == "confirmed" ? "Confermata" : "Attesa Pag.")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(team.overallStatus == "confirmed"
                                    ? Color.kartSuccess.opacity(0.2)
                                    : Color.kartWarning.opacity(0.2))
                        .foregroundColor(team.overallStatus == "confirmed" ? .kartSuccess : .kartWarning)
                        .cornerRadius(5)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.kartPanel)
            
            Divider().background(Color.kartBorder(opacity: 0.08))
            
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
                                    .foregroundColor(.kartForeground)
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
                        
                        if member.hasSignedRelease == true {
                            Image(systemName: "signature")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.kartSuccess)
                                .padding(4)
                                .background(Color.kartSuccess.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    
                    if member.id != team.members.last?.id {
                        Divider()
                            .background(Color.kartForeground.opacity(0.05))
                            .padding(.leading, 52)
                    }
                }
            }
            .background(Color.kartPanel.opacity(0.6))
            
            Divider().background(Color.kartBorder(opacity: 0.08))
            
            // Tre azioni restano affiancate; quattro mantengono la disposizione adattiva.
            LazyVGrid(
                columns: team.overallStatus == "waitlist" || team.overallStatus == "confirmed"
                    ? Array(repeating: GridItem(.flexible(minimum: 0), spacing: 8), count: 3)
                    : [GridItem(.adaptive(minimum: 140), spacing: 8)],
                spacing: 8
            ) {
                if team.overallStatus == "waitlist" {
                    Button {
                        acceptWaitlistTeam(teamId: team.teamId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                            Text("Accetta Iscrizione")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.kartSuccess)
                        .foregroundColor(.kartOnSuccess)
                        .cornerRadius(7)
                    }
                    .buttonStyle(KartPressButtonStyle())
                } else if team.overallStatus != "confirmed" {
                    Button {
                        confirmTeam(teamId: team.teamId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Conferma")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.kartSuccess)
                        .foregroundColor(.kartOnSuccess)
                        .cornerRadius(7)
                    }
                    .buttonStyle(KartPressButtonStyle())
                    
                    Button {
                        moveToWaitlistTeam(teamId: team.teamId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.fill")
                            Text("Attesa")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(7)
                    }
                    .buttonStyle(KartPressButtonStyle())
                } else if team.overallStatus == "confirmed" {
                    Button {
                        unconfirmTeam(teamId: team.teamId)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Revoca")
                        }
                        .font(.system(size: 11, weight: .bold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Color.kartWarning)
                        .foregroundColor(.kartOnWarning)
                        .cornerRadius(7)
                    }
                    .buttonStyle(KartPressButtonStyle())
                }
                
                Button {
                    teamToEdit = team
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Modifica")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.kartForeground.opacity(0.06))
                    .foregroundColor(.kartForeground)
                    .cornerRadius(7)
                }
                .buttonStyle(KartPressButtonStyle())
                
                Button {
                    deleteTeam(teamId: team.teamId)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Rimuovi")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.kartRed)
                    .foregroundColor(.white)
                    .cornerRadius(7)
                }
                .buttonStyle(KartPressButtonStyle())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.kartPanel.opacity(0.4))
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    team.overallStatus == "confirmed"
                        ? Color.kartSuccess.opacity(0.2)
                        : Color.kartForeground.opacity(0.07),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 16)
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
                    Circle().fill(Color.kartForeground.opacity(0.07))
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
            .background(Color.kartForeground.opacity(0.06))
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
                    HStack {
                        Text(reg.username ?? reg.email ?? "Utente")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.kartForeground)
                        
                        if reg.hasSignedRelease == true {
                            Image(systemName: "signature")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.kartSuccess)
                                .padding(4)
                                .background(Color.kartSuccess.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    if let email = reg.email, reg.username != nil {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundColor(.kartDim)
                    }
                }
                
                Spacer()
                
                if reg.status == "waitlist" {
                    Text("Lista d'Attesa")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .cornerRadius(4)
                } else if reg.status == "confirmed" {
                    Text("Confermata")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.kartSuccess.opacity(0.2))
                        .foregroundColor(.kartSuccess)
                        .cornerRadius(4)
                } else {
                    Text("Attesa Pag.")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.kartWarning.opacity(0.2))
                        .foregroundColor(.kartWarning)
                        .cornerRadius(4)
                }
            }


            HStack(spacing: 8) {
                if reg.status == "waitlist" && reg.teamId == nil && isTeamEvent {
                    Button {
                        registrationToAssign = reg
                    } label: {
                        Text("Accorpa a Team")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.kartInfoAction)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(KartPressButtonStyle())
                }
                
                if !(isTeamEvent && reg.teamId == nil) {
                    if reg.status == "waitlist" {
                        Button {
                            acceptWaitlistIndividual(registrationId: reg.id)
                        } label: {
                            Text("Accetta Iscrizione")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(Color.kartSuccess)
                                .foregroundColor(.kartOnSuccess)
                                .cornerRadius(6)
                        }
                        .buttonStyle(KartPressButtonStyle())
                    } else if reg.status != "confirmed" {
                        Button {
                            confirmIndividual(registrationId: reg.id)
                        } label: {
                            Text("Conferma")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(Color.kartSuccess)
                                .foregroundColor(.kartOnSuccess)
                                .cornerRadius(6)
                        }
                        .buttonStyle(KartPressButtonStyle())
                        
                        Button {
                            moveToWaitlistIndividual(registrationId: reg.id)
                        } label: {
                            Text("Attesa")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                        .buttonStyle(KartPressButtonStyle())
                    } else if reg.status == "confirmed" {
                        Button {
                            unconfirmIndividual(registrationId: reg.id)
                        } label: {
                            Text("Revoca")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(Color.kartWarning)
                                .foregroundColor(.kartOnWarning)
                                .cornerRadius(6)
                        }
                        .buttonStyle(KartPressButtonStyle())
                    }
                }
                
                Button {
                    deleteIndividual(registrationId: reg.id)
                } label: {
                        Text("Rimuovi")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.kartRed)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(KartPressButtonStyle())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.top, 4)
        }
        .padding(14)
        .background(Color.kartPanel)
        .cornerRadius(12)
        .padding(.horizontal, 16)
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
                        .fill(Color.kartForeground.opacity(0.07))
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
            let group = DispatchGroup()
            
            group.enter()
            viewModel.fetchTeamRegistrations(serverURL: server.httpURL, eventId: event.id, token: token) { loadedTeams in
                self.teams = loadedTeams ?? []
                group.leave()
            }
            
            group.enter()
            viewModel.fetchUnassignedRegistrations(serverURL: server.httpURL, eventId: event.id, token: token) { loadedUnassigned in
                self.unassignedRegistrations = loadedUnassigned ?? []
                group.leave()
            }
            
            group.notify(queue: .main) {
                self.isLoading = false
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
    
    private func unconfirmTeam(teamId: String) {
        guard let token = authState.currentToken else { return }
        viewModel.adminUnconfirmTeamRegistration(serverURL: server.httpURL, eventId: event.id, teamId: teamId, token: token) { success in
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
    
    private func confirmIndividual(registrationId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.adminConfirmIndividualRegistration(serverURL: server.httpURL, eventId: event.id, registrationId: registrationId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    private func unconfirmIndividual(registrationId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.adminUnconfirmIndividualRegistration(serverURL: server.httpURL, eventId: event.id, registrationId: registrationId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    private func deleteIndividual(registrationId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.adminDeleteIndividualRegistration(serverURL: server.httpURL, eventId: event.id, registrationId: registrationId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    // MARK: - Actions (Waitlist)
    
    private func acceptWaitlistTeam(teamId: String) {
        guard let token = authState.currentToken else { return }
        viewModel.adminAcceptWaitlistTeamRegistration(serverURL: server.httpURL, eventId: event.id, teamId: teamId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    private func acceptWaitlistIndividual(registrationId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.adminAcceptWaitlistRegistration(serverURL: server.httpURL, eventId: event.id, registrationId: registrationId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    private func moveToWaitlistTeam(teamId: String) {
        guard let token = authState.currentToken else { return }
        viewModel.adminMoveToWaitlistTeamRegistration(serverURL: server.httpURL, eventId: event.id, teamId: teamId, token: token) { success in
            if success { loadRegistrations() }
        }
    }
    
    private func moveToWaitlistIndividual(registrationId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.adminMoveToWaitlistRegistration(serverURL: server.httpURL, eventId: event.id, registrationId: registrationId, token: token) { success in
            if success { loadRegistrations() }
        }
    }

    // MARK: - CSV Import

    private func uploadCSV(url: URL) {
        guard let serverURL = server.httpURL,
              let token     = authState.currentToken else { return }

        isUploadingCSV = true

        // Accesso sicuro al file scelto dal picker
        guard url.startAccessingSecurityScopedResource() else {
            csvImportMessage = "Permesso negato per accedere al file."
            csvImportAlert   = true
            isUploadingCSV   = false
            return
        }

        defer { url.stopAccessingSecurityScopedResource() }

        let csvData: Data
        do {
            csvData = try Data(contentsOf: url)
        } catch {
            csvImportMessage = "Impossibile leggere il file: \(error.localizedDescription)"
            csvImportAlert   = true
            isUploadingCSV   = false
            return
        }

        let endpoint = serverURL.appendingPathComponent("events/\(event.id)/results/import_csv")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let crlf = "\r\n"
        var body = Data()
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"classifica.csv\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: text/csv\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(csvData)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        request.httpBody = body

        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isUploadingCSV = false

                if let error {
                    self.csvImportMessage = "Errore di rete: \(error.localizedDescription)"
                    self.csvImportAlert   = true
                    return
                }
                guard let http = response as? HTTPURLResponse else { return }

                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let imported = json["imported"] as? Int ?? 0
                    let errors   = json["errors"]   as? [String] ?? []

                    if http.statusCode == 200 {
                        var msg = "✅ Importati \(imported) risultati."
                        if !errors.isEmpty {
                            msg += "\n\n⚠️ \(errors.count) errori:\n" + errors.prefix(5).joined(separator: "\n")
                            if errors.count > 5 { msg += "\n…e altri \(errors.count - 5) errori." }
                        }
                        self.csvImportMessage = msg
                    } else {
                        let detail = json["detail"] as? String ?? "Errore \(http.statusCode)"
                        self.csvImportMessage = "❌ \(detail)"
                    }
                } else {
                    self.csvImportMessage = "❌ Risposta non valida dal server (\(http.statusCode))"
                }
                self.csvImportAlert = true
            }
        }.resume()
    }
}

// MARK: - Admin Team Selection Sheet

struct AdminTeamSelectionSheet: View {
    let server: DiscoveredServer
    @ObservedObject var viewModel: EventsViewModel
    let event: RaceEvent
    let registration: EventRegistrationWithUserResponse
    let availableTeams: [TeamRegistrationResponse]
    
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    
    @State private var isAssigning = false
    @State private var errorMessage: String? = nil
    
    @State private var showCreateForm = false
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if availableTeams.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 40))
                                .foregroundColor(.kartWarning)
                            Text("Nessuna squadra disponibile.")
                                .foregroundColor(.kartForeground)
                                .font(.headline)
                            Text("Non ci sono squadre che hanno posti liberi e accettano piloti extra.")
                                .foregroundColor(.kartDim)
                                .multilineTextAlignment(.center)
                                .font(.subheadline)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        List {
                            if let error = errorMessage {
                                Section {
                                    RegistrationErrorBanner(message: error)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets())
                                }
                            }
                            
                            Section(header: Text("Squadre Disponibili").foregroundColor(.kartAccent)) {
                                ForEach(availableTeams) { team in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(team.teamName)
                                                .font(.headline)
                                                .foregroundColor(.kartForeground)
                                            let maxP = event.maxPeoplePerGroup ?? 1
                                            Text("Posti liberi: \(maxP - team.members.count)")
                                                .font(.caption)
                                                .foregroundColor(.kartDim)
                                        }
                                        Spacer()
                                        
                                        Button {
                                            assign(to: team.teamId)
                                        } label: {
                                            if isAssigning {
                                                ProgressView().tint(.white)
                                                    .frame(width: 70, height: 30)
                                                    .background(Color.kartInfoAction)
                                                    .cornerRadius(6)
                                            } else {
                                                Text("Scegli")
                                                    .font(.system(size: 13, weight: .bold))
                                                    .frame(width: 70, height: 30)
                                                    .background(Color.kartInfoAction)
                                                    .foregroundColor(.white)
                                                    .cornerRadius(6)
                                            }
                                        }
                                        .buttonStyle(KartPressButtonStyle())
                                        .disabled(isAssigning)
                                    }
                                    .padding(.vertical, 6)
                                    .listRowBackground(Color.kartPanel)
                                }
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
                    }
                }
            }
            .navigationTitle("Seleziona Squadra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showCreateForm = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                    }
                    .foregroundColor(.kartAccent)
                }
            }
            .sheet(isPresented: $showCreateForm) {
                AdminCreateTeamFormSheet(
                    server: server,
                    viewModel: viewModel,
                    event: event,
                    leaderRegistration: registration,
                    onSuccess: {
                        dismiss()
                    }
                )
            }
        }
    }
    
    private func assign(to teamId: String) {
        guard let token = authState.currentToken else { return }
        isAssigning = true
        errorMessage = nil
        
        viewModel.adminAssignToTeam(serverURL: server.httpURL, eventId: event.id, teamId: teamId, registrationIds: [registration.id], token: token) { success in
            isAssigning = false
            if success {
                dismiss()
            } else {
                errorMessage = "Impossibile assegnare il pilota alla squadra."
            }
        }
    }
}
// MARK: - Admin Create Team Form Sheet

struct AdminCreateTeamFormSheet: View {
    let server: DiscoveredServer
    @ObservedObject var viewModel: EventsViewModel
    let event: RaceEvent
    let leaderRegistration: EventRegistrationWithUserResponse
    let onSuccess: () -> Void
    
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    
    @State private var teamName: String = ""
    @State private var acceptsExtraPilots: Bool = true
    
    @State private var isCreating = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                Form {
                    if let error = errorMessage {
                        Section {
                            RegistrationErrorBanner(message: error)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                    
                    Section(header: Text("Dettagli Nuova Squadra").foregroundColor(.kartAccent)) {
                        TextField("Nome della squadra", text: $teamName)
                            .foregroundColor(.kartForeground)
                            .disableAutocorrection(true)
                            .autocapitalization(.words)
                        
                        Toggle("Accetta piloti extra", isOn: $acceptsExtraPilots)
                            .tint(.kartAccent)
                            .foregroundColor(.kartForeground)
                    }
                    .listRowBackground(Color.kartPanel)
                    
                    Section {
                        Button {
                            createTeam()
                        } label: {
                            HStack {
                                Spacer()
                                if isCreating {
                                    ProgressView().tint(.kartForeground)
                                } else {
                                    Text("Crea Squadra")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.kartForeground)
                                }
                                Spacer()
                            }
                        }
                        .disabled(teamName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                        .listRowBackground(
                            (teamName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                                ? Color.gray
                                : Color.kartInfoAction
                        )
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Nuova Squadra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
        }
    }
    
    private func createTeam() {
        guard let token = authState.currentToken else { return }
        let cleanName = teamName.trimmingCharacters(in: .whitespaces)
        guard !cleanName.isEmpty else { return }
        
        isCreating = true
        errorMessage = nil
        
        viewModel.adminCreateTeamFromIndividuals(
            serverURL: server.httpURL,
            eventId: event.id,
            teamName: cleanName,
            leaderId: leaderRegistration.id,
            memberIds: [],
            acceptsExtraPilots: acceptsExtraPilots,
            token: token
        ) { success in
            isCreating = false
            if success {
                onSuccess()
                dismiss()
            } else {
                errorMessage = "Impossibile creare la squadra."
            }
        }
    }
}

