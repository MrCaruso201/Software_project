import SwiftUI

struct AdminAddRegistrationSheetView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent
    let isTeamEvent: Bool
    
    @Environment(\.dismiss) var dismiss
    
    // Individual fields
    @State private var email: String = ""
    
    // Team fields
    @State private var teamName: String = ""
    @State private var leaderEmail: String = ""
    @State private var memberEmails: [String] = []
    
    @State private var isSaving = false
    @State private var errorMessage: String? = nil
    
    private var maxAdditionalMembers: Int {
        max(0, (event.maxPeoplePerGroup ?? 1) - 1)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RegistrationHeaderSection(event: event, isTeamEvent: isTeamEvent)
                        
                        Divider().background(Color.kartBorder(opacity: 0.1))
                        
                        if isTeamEvent {
                            teamForm
                        } else {
                            individualForm
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
                                    .background(Color.kartAccent)
                                    .cornerRadius(10)
                            } else {
                                Text("Aggiungi Iscrizione")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.kartAccent)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                        }
                        .disabled(isSaving || !isValid)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Nuova Iscrizione")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
            .onAppear {
                // Inizializzazione se necessaria
            }
        }
    }
    
    private var individualForm: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Email, @Username o Nome Pilota")
                .font(.headline)
                .foregroundColor(.kartForeground)
            
            TextField("Email, @Username o Nome", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding()
                .background(Color.kartForeground.opacity(0.05))
                .cornerRadius(8)
                .foregroundColor(.kartForeground)
        }
    }
    
    private var teamForm: some View {
        VStack(alignment: .leading, spacing: 15) {
            TeamFormSection(
                teamName: $teamName,
                leaderEmail: $leaderEmail,
                memberEmails: $memberEmails,
                maxAdditionalMembers: maxAdditionalMembers,
                isLeaderEditable: true
            )
        }
    }
    
    private var isValid: Bool {
        if isTeamEvent {
            return !teamName.trimmingCharacters(in: .whitespaces).isEmpty &&
                   !leaderEmail.trimmingCharacters(in: .whitespaces).isEmpty
        } else {
            return !email.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    
    private func performSave() {
        isSaving = true
        errorMessage = nil
        
        if isTeamEvent {
            let validEmails = memberEmails
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
                
            viewModel.adminRegisterTeam(
                serverURL: server.httpURL,
                eventId: event.id,
                token: authState.currentToken,
                teamName: teamName.trimmingCharacters(in: .whitespaces),
                leaderEmail: leaderEmail.trimmingCharacters(in: .whitespaces),
                memberEmails: validEmails
            ) { success, errorMsg in
                isSaving = false
                if success {
                    dismiss()
                } else {
                    errorMessage = errorMsg ?? "Errore sconosciuto"
                }
            }
        } else {
            viewModel.adminRegisterIndividual(
                serverURL: server.httpURL,
                eventId: event.id,
                token: authState.currentToken,
                email: email.trimmingCharacters(in: .whitespaces).lowercased()
            ) { success, errorMsg in
                isSaving = false
                if success {
                    dismiss()
                } else {
                    errorMessage = errorMsg ?? "Errore sconosciuto"
                }
            }
        }
    }
}
