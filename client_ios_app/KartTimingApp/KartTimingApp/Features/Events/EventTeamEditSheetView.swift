import SwiftUI

struct EventTeamEditSheetView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let event: RaceEvent
    let registration: EventRegistrationResponse
    var isAdmin: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    @State private var teamName: String = ""
    @State private var leaderEmail: String = ""
    @State private var memberEmails: [String] = []
    
    @State private var acceptsExtraPilots: Bool = false
    
    @State private var isFetching = true
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    private var maxAdditionalMembers: Int {
        max(0, (event.maxPeoplePerGroup ?? Int.max) - 1)
    }
    
    private var minAdditionalMembers: Int { max(0, (event.minPeoplePerGroup ?? 1) - 1) }

    private var canSave: Bool {
        let leader = leaderEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let members = memberEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let identifiers = [leader] + members

        return !isFetching && !isSaving && registration.teamId != nil &&
            !teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !leader.isEmpty &&
            members.count >= minAdditionalMembers &&
            members.count <= maxAdditionalMembers &&
            Set(identifiers).count == identifiers.count
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                if isFetching {
                    ProgressView("Caricamento team...")
                        .foregroundColor(.kartForeground)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            RegistrationHeaderSection(event: event, isTeamEvent: true, showDeadlineBanner: false)
                            Divider().background(Color.kartBorder(opacity: 0.1))
                            
                            TeamFormSection(
                                teamName: $teamName,
                                leaderEmail: $leaderEmail,
                                memberEmails: $memberEmails,
                                maxAdditionalMembers: maxAdditionalMembers,
                                minAdditionalMembers: minAdditionalMembers,
                                isLeaderEditable: isAdmin
                            )
                            
                            let filledCount = memberEmails.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
                            if filledCount < maxAdditionalMembers {
                                Toggle("Accetto membri extra accorpati dagli admin", isOn: $acceptsExtraPilots)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.kartForeground)
                                    .tint(.kartAccent)
                            }
                            
                            if let error = errorMessage {
                                RegistrationErrorBanner(message: error)
                            }
                            
                            Spacer(minLength: 30)
                            
                            Button {
                                performSave()
                            } label: {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.gray.opacity(0.4))
                                        .cornerRadius(10)
                                } else {
                                    Text("Salva Modifiche")
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(canSave ? Color.kartGreen : Color.gray.opacity(0.4))
                                        .foregroundColor(canSave ? .white : .secondary)
                                        .cornerRadius(10)
                                }
                            }
                            .disabled(isSaving || !canSave)
                            
                            if !isAdmin && registration.status != "confirmed" {
                                Button {
                                    performCancelRegistration()
                                } label: {
                                    Text("Annulla Iscrizione Team")
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.kartRed)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                                .padding(.top, 10)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("Modifica Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartForeground)
                }
            }
            .onAppear {
                fetchTeamDetails()
            }
        }
    }
    
    private func fetchTeamDetails() {
        guard let token = authState.currentToken, let teamId = registration.teamId else {
            errorMessage = "Errore: ID team mancante"
            isFetching = false
            return
        }
        
        guard let url = server.httpURL?.appendingPathComponent("events/\(event.id)/registrations/team/\(teamId)") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isFetching = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200, let data = data {
                    if let teamResponse = try? JSONDecoder().decode(TeamRegistrationResponse.self, from: data) {
                        self.teamName = teamResponse.teamName
                        if let leader = teamResponse.members.first(where: { $0.isTeamLeader }) {
                            self.leaderEmail = leader.username.map { "@\($0)" } ?? leader.email ?? ""
                        }
                        // Escludiamo il leader
                        let otherMembers = teamResponse.members.filter { !$0.isTeamLeader }
                        self.memberEmails = otherMembers.compactMap { $0.username.map { "@\($0)" } ?? $0.email }
                        self.acceptsExtraPilots = teamResponse.acceptsExtraPilots
                        
                        if self.memberEmails.count < minAdditionalMembers {
                            self.memberEmails += Array(repeating: "", count: minAdditionalMembers - self.memberEmails.count)
                        }
                    } else {
                        self.errorMessage = "Errore di decodifica dei dati del team"
                    }
                } else {
                    self.errorMessage = "Impossibile recuperare il team"
                }
            }
        }.resume()
    }
    
    private func performSave() {
        guard canSave, let teamId = registration.teamId else { return }
        isSaving = true
        errorMessage = nil
        
        let validEmails = memberEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let acceptsExtra = (validEmails.count < maxAdditionalMembers) ? acceptsExtraPilots : false
            
        viewModel.updateTeamRegistration(
            serverURL: server.httpURL,
            eventId: event.id,
            teamId: teamId,
            token: authState.currentToken,
            teamName: teamName.trimmingCharacters(in: .whitespacesAndNewlines),
            memberEmails: validEmails,
            leaderEmail: isAdmin ? leaderEmail.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            acceptsExtraPilots: acceptsExtra
        ) { success, errorMsg in
            isSaving = false
            if success {
                dismiss()
            } else {
                self.errorMessage = errorMsg ?? "Errore sconosciuto"
            }
        }
    }
    
    private func performCancelRegistration() {
        if let token = authState.currentToken {
            viewModel.unregisterFromEvent(serverURL: server.httpURL, eventId: event.id, token: token) { success, _ in
                if success {
                    dismiss()
                }
            }
        }
    }
}
