import SwiftUI

struct EventTeamEditSheetView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent
    let registration: EventRegistrationResponse
    var isAdmin: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    @State private var teamName: String = ""
    @State private var leaderEmail: String = ""
    @State private var memberEmails: [String] = []
    
    @State private var isFetching = true
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    private var maxAdditionalMembers: Int {
        max(0, (event.maxPeoplePerGroup ?? 1) - 1)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                if isFetching {
                    ProgressView("Caricamento team...")
                        .foregroundColor(.white)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            RegistrationHeaderSection(event: event, isTeamEvent: true)
                            Divider().background(Color.white.opacity(0.1))
                            
                            TeamFormSection(
                                teamName: $teamName,
                                leaderEmail: $leaderEmail,
                                memberEmails: $memberEmails,
                                maxAdditionalMembers: maxAdditionalMembers,
                                isLeaderEditable: isAdmin
                            )
                            
                            if let error = errorMessage {
                                RegistrationErrorBanner(message: error)
                            }
                            
                            Spacer(minLength: 30)
                            
                            Button {
                                performSave()
                            } label: {
                                if isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.kartAccent)
                                        .cornerRadius(10)
                                } else {
                                    Text("Salva Modifiche")
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.kartAccent)
                                        .foregroundColor(.black)
                                        .cornerRadius(10)
                                }
                            }
                            .disabled(isSaving || teamName.trimmingCharacters(in: .whitespaces).isEmpty)
                            
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
                            self.leaderEmail = leader.email ?? ""
                        }
                        // Escludiamo il leader
                        let otherMembers = teamResponse.members.filter { !$0.isTeamLeader }
                        self.memberEmails = otherMembers.compactMap { $0.email }
                        
                        // Non forziamo alcun campo vuoto
                        // if self.memberEmails.isEmpty {
                        //     self.memberEmails.append("")
                        // }
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
        guard let teamId = registration.teamId else { return }
        isSaving = true
        errorMessage = nil
        
        let validEmails = memberEmails
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
            
        viewModel.updateTeamRegistration(
            serverURL: server.httpURL,
            eventId: event.id,
            teamId: teamId,
            token: authState.currentToken,
            teamName: teamName.trimmingCharacters(in: .whitespaces),
            memberEmails: validEmails,
            leaderEmail: isAdmin ? leaderEmail.trimmingCharacters(in: .whitespaces) : nil
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
