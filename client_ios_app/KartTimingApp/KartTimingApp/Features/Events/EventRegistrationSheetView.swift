import SwiftUI

// MARK: - Main Sheet

struct EventRegistrationSheetView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: EventsViewModel
    let event: RaceEvent

    @Environment(\.dismiss) var dismiss

    @State private var isRegistering = false
    @State private var errorMessage: String? = nil
    @State private var teamName: String = ""
    @State private var leaderEmail: String = ""
    @State private var memberEmails: [String] = [""]
    
    @State private var wantsToBeGrouped: Bool = true
    @State private var acceptsExtraPilots: Bool = false

    private var isTeamEvent: Bool { event.isTeamEvent }
    private var maxAdditionalMembers: Int { max(0, (event.maxPeoplePerGroup ?? 1) - 1) }
    private var isDeadlinePassed: Bool { event.isDeadlinePassed }
    
    private var filledEmailsCount: Int {
        memberEmails.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }
    
    private var isButtonEnabled: Bool {
        guard isTeamEvent else { return true }
        if filledEmailsCount == 0 && wantsToBeGrouped { return true }
        return !teamName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RegistrationHeaderSection(event: event, isTeamEvent: isTeamEvent)
                        Divider().background(Color.kartBorder(opacity: 0.1))
                        RegistrationDetailsSection(event: event, isTeamEvent: isTeamEvent)
                        Divider().background(Color.kartBorder(opacity: 0.1))
                        if isTeamEvent {
                            TeamFormSection(
                                teamName: $teamName,
                                leaderEmail: $leaderEmail,
                                memberEmails: $memberEmails,
                                maxAdditionalMembers: maxAdditionalMembers,
                                isLeaderEditable: false
                            )
                            
                            if filledEmailsCount == 0 {
                                Toggle("Voglio essere accorpato ad una squadra", isOn: $wantsToBeGrouped)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.kartForeground)
                                    .tint(.kartAccent)
                                    .padding(.top, 10)
                            } else if filledEmailsCount < maxAdditionalMembers {
                                Toggle("Accetto membri extra accorpati dagli admin", isOn: $acceptsExtraPilots)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.kartForeground)
                                    .tint(.kartAccent)
                                    .padding(.top, 10)
                            }
                        }
                        registrationNote
                        if let error = errorMessage {
                            RegistrationErrorBanner(message: error)
                        }
                        Spacer(minLength: 30)
                        RegistrationButton(
                            isTeamEvent: isTeamEvent,
                            isEnabled: isButtonEnabled,
                            isLoading: isRegistering,
                            isDeadlinePassed: isDeadlinePassed,
                            action: performRegistration
                        )
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Iscrizione Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
            .onAppear {
                fetchUserEmail()
            }
        }
    }

    // MARK: - Fetch User Email

    private func fetchUserEmail() {
        guard let token = authState.currentToken,
              let url = server.httpURL?.appendingPathComponent("auth/me") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, _, _ in
            if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let email = json["email"] as? String {
                DispatchQueue.main.async {
                    self.leaderEmail = email
                }
            }
        }.resume()
    }

    // MARK: - Note

    private var registrationNote: some View {
        let text: String
        if isDeadlinePassed {
            // Nota specifica per iscrizioni post-deadline
            text = "Le iscrizioni per questo evento sono chiuse. Proseguendo entrerai in lista d'attesa: riceverai una notifica se verrai accettato dall'organizzatore."
        } else if !isTeamEvent {
            text = "Cliccando su Conferma Iscrizione, ti registrerai ufficialmente all'evento."
        } else {
            if filledEmailsCount == 0 {
                if wantsToBeGrouped {
                    text = "Non avendo inserito compagni, sarai messo in lista d'attesa. Pagherai l'iscrizione il giorno dell'evento."
                } else {
                    text = "Creerai una squadra da solo. Pagherai l'intera quota, ma potrai aggiungere membri in futuro."
                }
            } else if filledEmailsCount < maxAdditionalMembers {
                if acceptsExtraPilots {
                    text = "I membri extra si accorperanno alla tua squadra il giorno dell'evento solo se i pagamenti verranno divisi correttamente in pista."
                } else {
                    text = "La tua squadra non accetterà piloti extra dagli admin."
                }
            } else {
                text = "Hai riempito tutti i posti disponibili per questa gara a squadre."
            }
        }
        return Text(text)
            .font(.footnote)
            .foregroundColor(isDeadlinePassed ? Color.orange.opacity(0.8) : Color.gray)
            .multilineTextAlignment(.leading)
            .padding(.top, 4)
    }

    // MARK: - Registration Logic

    private func performRegistration() {
        guard let token = authState.currentToken else {
            errorMessage = "Devi essere loggato per iscriverti."
            return
        }
        isRegistering = true
        errorMessage = nil

        if isTeamEvent {
            let validEmails = memberEmails.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
            
            if validEmails.isEmpty && wantsToBeGrouped {
                viewModel.registerToEvent(
                    serverURL: server.httpURL,
                    eventId: event.id,
                    token: token
                ) { success, msg in
                    isRegistering = false
                    if success { dismiss() } else { errorMessage = msg ?? "Errore sconosciuto." }
                }
            } else {
                var finalTeamName = teamName.trimmingCharacters(in: .whitespaces)
                if finalTeamName.isEmpty && validEmails.isEmpty {
                    let shortEmail = leaderEmail.components(separatedBy: "@").first ?? "Anon"
                    finalTeamName = "Team \(shortEmail)"
                }
                
                let acceptsExtra = (validEmails.count < maxAdditionalMembers) ? acceptsExtraPilots : false
                
                viewModel.registerToEvent(
                    serverURL: server.httpURL,
                    eventId: event.id,
                    token: token,
                    teamName: finalTeamName,
                    memberEmails: validEmails,
                    acceptsExtraPilots: acceptsExtra
                ) { success, msg in
                    isRegistering = false
                    if success { dismiss() } else { errorMessage = msg ?? "Errore sconosciuto." }
                }
            }
        } else {
            viewModel.registerToEvent(
                serverURL: server.httpURL,
                eventId: event.id,
                token: token
            ) { success, msg in
                isRegistering = false
                if success { dismiss() } else { errorMessage = msg ?? "Errore sconosciuto." }
            }
        }
    }
}

// MARK: - Header Section

struct RegistrationHeaderSection: View {
    let event: RaceEvent
    let isTeamEvent: Bool
    var showDeadlineBanner: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.kartForeground)

            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundColor(.kartAccent)
                Text(event.formattedDate).foregroundColor(.kartDim)
            }

            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundColor(.kartAccent)
                Text(event.location).foregroundColor(.kartDim)
            }

            if isTeamEvent {
                TeamEventBadge(maxPeople: event.maxPeoplePerGroup ?? 2)
            } else {
                IndividualEventBadge()
            }

            // Banner deadline visibile solo in fase di nuova iscrizione
            if showDeadlineBanner && event.isDeadlinePassed {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "clock.badge.exclamationmark.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.kartForeground)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DEADLINE SCADUTA")
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(.kartForeground)
                        Text("Verrai posizionato in lista d'attesa. Controlla le notifiche: riceverai un avviso se l'organizzatore ti accetta.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.kartSecondaryText(opacity: 0.88))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.85, green: 0.15, blue: 0.1), Color(red: 0.7, green: 0.08, blue: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                )
                .padding(.top, 4)
            } else if showDeadlineBanner && event.isDeadlineApproaching, let dl = event.deadlineObject {
                let daysLeft = max(0, Int(dl.timeIntervalSince(Date()) / 86400))
                let hoursLeft = max(0, Int(dl.timeIntervalSince(Date()) / 3600))
                let timeLabel = daysLeft > 0 ? "\(daysLeft) giorn\(daysLeft == 1 ? "o" : "i")" : "\(hoursLeft) or\(hoursLeft == 1 ? "a" : "e")"
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                    Text("Iscrizioni in scadenza: \(timeLabel) rimast\(daysLeft == 1 || hoursLeft == 1 ? "o" : "i")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.yellow)
                .cornerRadius(10)
                .padding(.top, 4)
            }
        }
        .padding(.top, 10)
    }
}

// MARK: - Team Badge

private struct TeamEventBadge: View {
    let maxPeople: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 11, weight: .bold))
            Text("GARA A SQUADRE — max \(maxPeople) persone")
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.82, blue: 0.0),
                         Color(red: 1.0, green: 0.6, blue: 0.0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .foregroundColor(.black)
        .clipShape(Capsule())
        .padding(.top, 4)
    }
}

private struct IndividualEventBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.system(size: 11, weight: .bold))
            Text("GARA INDIVIDUALE")
                .font(.system(size: 11, weight: .bold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            LinearGradient(
                colors: [Color.cyan, Color.blue],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .foregroundColor(.kartForeground)
        .clipShape(Capsule())
        .padding(.top, 4)
    }
}

// MARK: - Details Section

private struct RegistrationDetailsSection: View {
    let event: RaceEvent
    let isTeamEvent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dettagli Evento")
                .font(.headline)
                .foregroundColor(.kartForeground)

            costRow
            weightRow
            participantsRow
        }
    }

    @ViewBuilder
    private var costRow: some View {
        if let cost = event.registrationCost {
            DetailRowView(label: "Prezzo di iscrizione", value: String(format: "€ %.2f", cost))
        } else {
            DetailRowView(label: "Prezzo di iscrizione", value: "Gratuito")
        }
    }

    @ViewBuilder
    private var weightRow: some View {
        if let weight = event.weightLimit {
            DetailRowView(label: "Peso minimo", value: String(format: "%.1f kg", weight))
        }
    }

    @ViewBuilder
    private var participantsRow: some View {
        if let maxPart = event.maxParticipants {
            DetailRowView(label: "Partecipanti massimi", value: "\(maxPart)")
        }
    }
}

// MARK: - Detail Row

private struct DetailRowView: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.kartDim)
            Spacer()
            Text(value).foregroundColor(.kartForeground).fontWeight(.medium)
        }
    }
}

// MARK: - Error Banner

struct RegistrationErrorBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.kartRed)
            Text(message)
                .foregroundColor(.kartRed)
                .font(.footnote)
        }
        .padding(10)
        .background(Color.kartRed.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Confirm Button

private struct RegistrationButton: View {
    let isTeamEvent: Bool
    let isEnabled: Bool
    let isLoading: Bool
    var isDeadlinePassed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView().tint(.kartDim).padding(.trailing, 5)
                }
                Image(systemName: isDeadlinePassed
                    ? "clock.badge.exclamationmark.fill"
                    : (isTeamEvent ? "person.3.fill" : "checkmark.circle.fill")
                )
                Text(isDeadlinePassed
                    ? "Lista d'Attesa"
                    : (isTeamEvent ? "Iscriviti con il Team" : "Conferma Iscrizione")
                )
                .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isEnabled && !isLoading ? Color.kartAction : Color.kartPanel)
            .foregroundColor(isEnabled && !isLoading ? .white : .kartDim)
            .cornerRadius(12)
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Team Form Section

struct TeamFormSection: View {
    @Binding var teamName: String
    @Binding var leaderEmail: String
    @Binding var memberEmails: [String]
    let maxAdditionalMembers: Int
    var isLeaderEditable: Bool = false

    private var filledCount: Int {
        memberEmails.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    private func removeMember(at index: Int) {
        var updated = memberEmails
        updated.remove(at: index)
        memberEmails = updated
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Dati Squadra")
                    .font(.headline)
                    .foregroundColor(.kartForeground)
                Spacer()
                Text("Membri: \(filledCount + 1)/\(maxAdditionalMembers + 1)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.kartAccent)
            }

            teamNameField
            leaderEmailField
            memberEmailsSection
        }
        .padding(14)
        .background(Color.kartForeground.opacity(0.04))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.kartAccent.opacity(0.2), lineWidth: 1)
        )
    }

    private var teamNameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nome Squadra", systemImage: "flag.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.kartDim)

            let isEmpty = teamName.trimmingCharacters(in: .whitespaces).isEmpty
            let borderColor: Color = isEmpty ? Color.kartForeground.opacity(0.15) : Color.kartAccent.opacity(0.6)

            TextField("Inserisci il nome della squadra", text: $teamName)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.kartForeground.opacity(0.07))
                .foregroundColor(.kartForeground)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor, lineWidth: 1))
                .autocorrectionDisabled()
        }
    }

    private var leaderEmailField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Email, @Username o Nome Caposquadra", systemImage: "star.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.kartForeground)
            
            let isEmpty = leaderEmail.trimmingCharacters(in: .whitespaces).isEmpty
            let borderColor: Color = isEmpty ? Color.kartForeground.opacity(0.15) : Color.kartAccent.opacity(0.6)
            
            TextField("Email, @Username o Nome", text: $leaderEmail)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(isLeaderEditable ? Color.kartForeground.opacity(0.07) : Color.kartForeground.opacity(0.02))
                .foregroundColor(isLeaderEditable ? .kartForeground : .gray)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor, lineWidth: 1))
                .autocorrectionDisabled()
                .disabled(!isLeaderEditable)
        }
    }

    private var memberEmailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Email, @Username o Nomi Compagni", systemImage: "envelope.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.kartDim)

            ForEach(Array(memberEmails.enumerated()), id: \.offset) { index, _ in
                EmailFieldRow(
                    index: index,
                    email: Binding(
                        get: { memberEmails[index] },
                        set: { memberEmails[index] = $0 }
                    ),
                    canRemove: true,
                    onRemove: {
                        withAnimation(.spring(response: 0.3)) {
                            removeMember(at: index)
                        }
                    }
                )
            }

            if memberEmails.count < maxAdditionalMembers {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        memberEmails.append("")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 16))
                        Text("Aggiungi compagno").font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.kartAccent)
                    .padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Email Field Row

private struct EmailFieldRow: View {
    let index: Int
    @Binding var email: String
    let canRemove: Bool
    let onRemove: () -> Void

    private var borderColor: Color {
        let t = email.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return Color.kartForeground.opacity(0.15) }
        return t.contains("@") ? Color.green.opacity(0.5) : Color.orange.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.kartAccent)
                .frame(width: 20)

            TextField("Email, @Username o Nome", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.kartForeground.opacity(0.07))
                .foregroundColor(.kartForeground)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor, lineWidth: 1))

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.kartRed)
                        .font(.system(size: 20))
                }
            }
        }
    }
}
