import SwiftUI

// MARK: - Team Member View (non-leader)
// Visualizza la composizione del team per un membro non-leader.
// Permette di abbandonare la squadra tramite il nuovo endpoint /me/leave.

struct TeamMemberView: View {
    let server: DiscoveredServer
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent
    let registration: EventRegistrationResponse

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss

    @State private var teamData: TeamRegistrationResponse? = nil
    @State private var isFetching = true
    @State private var isLeaving = false
    @State private var errorMessage: String? = nil
    @State private var showLeaveConfirm = false

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
                            RegistrationHeaderSection(
                                event: event,
                                isTeamEvent: true,
                                showDeadlineBanner: false
                            )
                            Divider().background(Color.white.opacity(0.1))

                            // Composizione team
                            if let team = teamData {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Squadra: \(team.teamName)")
                                        .font(.system(size: 17, weight: .bold))
                                        .foregroundColor(.white)

                                    ForEach(team.members, id: \.registrationId) { member in
                                        memberRow(member)
                                    }
                                }
                            }

                            if let error = errorMessage {
                                RegistrationErrorBanner(message: error)
                            }

                            Spacer(minLength: 30)

                            // Pulsante Abbandona
                            Button {
                                showLeaveConfirm = true
                            } label: {
                                if isLeaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(Color.red.opacity(0.8))
                                        .cornerRadius(10)
                                } else {
                                    HStack(spacing: 8) {
                                        Image(systemName: "person.fill.xmark")
                                        Text("Abbandona squadra")
                                            .font(.system(size: 16, weight: .bold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.red.opacity(0.85))
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                            .disabled(isLeaving)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Il tuo team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
            .onAppear { fetchTeam() }
            .alert("Abbandona squadra", isPresented: $showLeaveConfirm) {
                Button("Abbandona", role: .destructive) { performLeave() }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Sei sicuro di voler abbandonare questa squadra? Non potrai essere reiscritto automaticamente.")
            }
        }
    }

    // MARK: - Member Row

    @ViewBuilder
    private func memberRow(_ member: TeamMemberResponse) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(member.isTeamLeader ? Color.kartAccent.opacity(0.2) : Color.white.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: member.isTeamLeader ? "star.fill" : "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(member.isTeamLeader ? .kartAccent : .white.opacity(0.6))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.username ?? member.email ?? "Utente sconosciuto")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if member.isTeamLeader {
                        Text("LEADER")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(.kartAccent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.kartAccent.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                
                if member.hasSignedRelease == true {
                    HStack(spacing: 4) {
                        Image(systemName: "signature")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                            .padding(4)
                            .background(Color.green.opacity(0.2))
                            .clipShape(Circle())
                        Text("Liberatoria firmata")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
                if let email = member.email {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            Spacer()

            if member.isTeamLeader {
                statusBadge(member.status)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case "confirmed":   return ("OK", .green)
            case "waitlist":    return ("Attesa", .purple)
            default:            return ("Pend.", .orange)
            }
        }()
        Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.8))
            .cornerRadius(5)
    }

    // MARK: - Network

    private func fetchTeam() {
        guard let teamId = registration.teamId,
              let token = authState.currentToken,
              let serverURL = server.httpURL else {
            isFetching = false
            return
        }

        let url = serverURL.appendingPathComponent("events/\(event.id)/registrations/team/\(teamId)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isFetching = false
                if let data = data,
                   let httpRes = response as? HTTPURLResponse,
                   httpRes.statusCode == 200,
                   let decoded = try? JSONDecoder().decode(TeamRegistrationResponse.self, from: data) {
                    teamData = decoded
                } else {
                    errorMessage = "Impossibile caricare i dati del team"
                }
            }
        }.resume()
    }

    private func performLeave() {
        isLeaving = true
        viewModel.leaveTeam(
            serverURL: server.httpURL,
            eventId: event.id,
            token: authState.currentToken
        ) { success, msg in
            isLeaving = false
            if success {
                dismiss()
            } else {
                errorMessage = msg ?? "Errore durante l'abbandono"
            }
        }
    }
}
