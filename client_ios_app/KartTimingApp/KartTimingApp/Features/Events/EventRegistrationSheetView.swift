import SwiftUI

// MARK: - Main Sheet

struct EventRegistrationSheetView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent

    @Environment(\.dismiss) var dismiss

    @State private var isRegistering = false
    @State private var errorMessage: String? = nil
    @State private var teamName: String = ""
    @State private var memberEmails: [String] = [""]

    private var isTeamEvent: Bool { event.isTeamEvent }
    private var maxAdditionalMembers: Int { max(0, (event.maxPeoplePerGroup ?? 1) - 1) }
    private var isButtonEnabled: Bool {
        guard isTeamEvent else { return true }
        return !teamName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        RegistrationHeaderSection(event: event, isTeamEvent: isTeamEvent)
                        Divider().background(Color.white.opacity(0.1))
                        RegistrationDetailsSection(event: event, isTeamEvent: isTeamEvent)
                        Divider().background(Color.white.opacity(0.1))
                        if isTeamEvent {
                            TeamFormSection(
                                teamName: $teamName,
                                memberEmails: $memberEmails,
                                maxAdditionalMembers: maxAdditionalMembers
                            )
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
                            action: performRegistration
                        )
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Iscrizione Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
        }
    }

    // MARK: - Note

    private var registrationNote: some View {
        let text = isTeamEvent
            ? "Inserisci il nome della squadra e le email dei tuoi compagni. Sarai tu il capogruppo e dovrai pagare l'iscrizione completa del team."
            : "Cliccando su Conferma Iscrizione, ti registrerai ufficialmente all'evento."
        return Text(text)
            .font(.footnote)
            .foregroundColor(.kartDim)
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
            let validEmails = memberEmails
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            viewModel.registerToEvent(
                serverURL: server.httpURL,
                eventId: event.id,
                token: token,
                teamName: teamName.trimmingCharacters(in: .whitespaces),
                memberEmails: validEmails
            ) { success, msg in
                isRegistering = false
                if success { dismiss() } else { errorMessage = msg ?? "Errore sconosciuto." }
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

private struct RegistrationHeaderSection: View {
    let event: RaceEvent
    let isTeamEvent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)

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

// MARK: - Details Section

private struct RegistrationDetailsSection: View {
    let event: RaceEvent
    let isTeamEvent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dettagli Evento")
                .font(.headline)
                .foregroundColor(.white)

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
            Text(value).foregroundColor(.white).fontWeight(.medium)
        }
    }
}

// MARK: - Error Banner

private struct RegistrationErrorBanner: View {
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView().tint(.black).padding(.trailing, 5)
                }
                Image(systemName: isTeamEvent ? "person.3.fill" : "checkmark.circle.fill")
                Text(isTeamEvent ? "Iscriviti con il Team" : "Conferma Iscrizione")
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(isEnabled ? Color.kartAccent : Color.gray.opacity(0.4))
            .foregroundColor(isEnabled ? .black : .white)
            .cornerRadius(10)
        }
        .disabled(!isEnabled || isLoading)
    }
}

// MARK: - Team Form Section

struct TeamFormSection: View {
    @Binding var teamName: String
    @Binding var memberEmails: [String]
    let maxAdditionalMembers: Int

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
                    .foregroundColor(.white)
                Spacer()
                Text("Membri: \(filledCount)/\(maxAdditionalMembers)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.kartAccent)
            }

            teamNameField
            memberEmailsSection
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
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
            let borderColor: Color = isEmpty ? Color.white.opacity(0.15) : Color.kartAccent.opacity(0.6)

            TextField("Inserisci il nome della squadra", text: $teamName)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Color.white.opacity(0.07))
                .foregroundColor(.white)
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(borderColor, lineWidth: 1))
                .autocorrectionDisabled()
        }
    }

    private var memberEmailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Email Compagni di Squadra", systemImage: "envelope.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.kartDim)

            ForEach(Array(memberEmails.enumerated()), id: \.offset) { index, _ in
                EmailFieldRow(
                    index: index,
                    email: Binding(
                        get: { memberEmails[index] },
                        set: { memberEmails[index] = $0 }
                    ),
                    canRemove: memberEmails.count > 1,
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
        if t.isEmpty { return Color.white.opacity(0.15) }
        return t.contains("@") ? Color.green.opacity(0.5) : Color.orange.opacity(0.5)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.kartAccent)
                .frame(width: 20)

            TextField("email@esempio.com", text: $email)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.07))
                .foregroundColor(.white)
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
