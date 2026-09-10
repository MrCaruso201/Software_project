import SwiftUI

/// Pannello per assegnare i kart alle iscrizioni (squadre o singoli)
struct KartAssignmentView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var manager: KartTimingManager

    struct RegistrationSelection: Identifiable {
        let id: String
        let defaultName: String
    }

    @State private var regToAssign: RegistrationSelection? = nil
    @State private var showAssignAlert = false
    @State private var assignKartNumberText = ""
    @State private var assignKartNameText = ""
    @State private var actionError: String? = nil
    
    // MARK: - Weight Edit State
    @State private var showWeightAlert = false
    @State private var weightInputValue = ""
    @State private var weightAlertRegistrationId: Int? = nil

    private var enrolledTeams: [TeamRegistrationResponse] {
        viewModel.registeredTeams.filter { $0.overallStatus != "waitlist" }
    }
    
    private var enrolledIndividuals: [EventRegistrationWithUserResponse] {
        viewModel.registeredIndividuals.filter { $0.status != "waitlist" }
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    if event.isTeamEvent {
                        if enrolledTeams.isEmpty {
                            emptyView
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(enrolledTeams) { team in
                                    teamCard(team)
                                }
                            }
                        }
                    } else {
                        if enrolledIndividuals.isEmpty {
                            emptyView
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(enrolledIndividuals) { reg in
                                    individualCard(reg)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
                .padding(.bottom, 30)
            }
        }
        .alert("Assegna Kart", isPresented: $showAssignAlert) {
            TextField("Numero Kart", text: $assignKartNumberText)
                .keyboardType(.numberPad)
            TextField("Username", text: $assignKartNameText)
            
            Button("Assegna") {
                guard let num = Int(assignKartNumberText), let reg = regToAssign else { return }
                Task {
                    do {
                        try await viewModel.assignKart(
                            teamId: reg.id,
                            kartNumber: num,
                            teamName: assignKartNameText.trimmingCharacters(in: .whitespaces).isEmpty ? reg.defaultName : assignKartNameText
                        )
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Inserisci il numero del kart e il nome esatto che appare sul monitor dei tempi in pista.")
        }
        .alert("Errore", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Imposta Peso", isPresented: $showWeightAlert) {
            TextField("Peso in kg (es. 75.5)", text: $weightInputValue)
                .keyboardType(.decimalPad)
            Button("Salva") {
                guard let regId = weightAlertRegistrationId else { return }
                // Convert comma to dot if needed, then to Double
                let normalizedInput = weightInputValue.replacingOccurrences(of: ",", with: ".")
                if let weight = Double(normalizedInput) {
                    Task {
                        do {
                            try await viewModel.updateRegistrationWeight(registrationId: regId, weight: weight)
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                }
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Inserisci il peso del pilota.")
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: event.isTeamEvent ? "person.3.fill" : "person.fill")
                .font(.system(size: 44))
                .foregroundColor(.kartDim.opacity(0.4))
            Text(event.isTeamEvent ? "Nessuna squadra iscritta" : "Nessun pilota iscritto")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.kartDim)
            Text("Le iscrizioni appariranno qui.")
                .font(.system(size: 12))
                .foregroundColor(.kartDim.opacity(0.6))
        }
        .padding(40)
    }
    
    // MARK: - Team Card
    
    private func teamCard(_ team: TeamRegistrationResponse) -> some View {
        let assignment = viewModel.kartAssignments.first(where: { $0.teamId == team.teamId })
        let penaltyCount = assignment != nil ? (viewModel.penaltiesByKart[assignment!.kartNumber]?.filter { !$0.isWarning }.count ?? 0) : 0
        let totalPenaltySeconds = assignment != nil ? viewModel.totalPenaltySeconds(for: assignment!.kartNumber) : 0
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header: Info Assegnazione
            assignmentHeader(
                assignment: assignment,
                defaultName: team.teamName,
                id: team.teamId,
                penaltyCount: penaltyCount,
                totalPenaltySeconds: totalPenaltySeconds
            )
            
            Divider().background(Color.kartBorder(opacity: 0.08))
            
            // Lista Membri
            VStack(spacing: 0) {
                ForEach(team.members) { member in
                    HStack(spacing: 10) {
                        memberFallbackIcon
                        
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
                        
                        weightButton(weight: member.weight, registrationId: member.registrationId)
                        
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
                        Divider().background(Color.kartBorder(opacity: 0.05)).padding(.leading, 52)
                    }
                }
            }
            .background(Color.kartPanel.opacity(0.6))
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.07), lineWidth: 1))
    }
    
    // MARK: - Individual Card
    
    private func individualCard(_ reg: EventRegistrationWithUserResponse) -> some View {
        let regIdStr = String(reg.id)
        let assignment = viewModel.kartAssignments.first(where: { $0.teamId == regIdStr })
        let penaltyCount = assignment != nil ? (viewModel.penaltiesByKart[assignment!.kartNumber]?.filter { !$0.isWarning }.count ?? 0) : 0
        let totalPenaltySeconds = assignment != nil ? viewModel.totalPenaltySeconds(for: assignment!.kartNumber) : 0
        let defaultName = reg.username ?? reg.email ?? "Utente"
        
        return VStack(alignment: .leading, spacing: 0) {
            assignmentHeader(
                assignment: assignment,
                defaultName: defaultName,
                id: regIdStr,
                penaltyCount: penaltyCount,
                totalPenaltySeconds: totalPenaltySeconds
            )
            
            Divider().background(Color.kartBorder(opacity: 0.08))
            
            HStack(spacing: 10) {
                memberFallbackIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(defaultName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.kartForeground)
                    if let email = reg.email, reg.username != nil {
                        Text(email)
                            .font(.system(size: 11))
                            .foregroundColor(.kartDim)
                    }
                }
                Spacer()
                weightButton(weight: reg.weight, registrationId: reg.id)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.kartPanel.opacity(0.6))
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.07), lineWidth: 1))
    }
    
    // MARK: - Shared Header
    
    private func assignmentHeader(assignment: LiveKartAssignment?, defaultName: String, id: String, penaltyCount: Int, totalPenaltySeconds: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(assignment != nil ? Color.kartAccent.opacity(0.12) : Color.kartForeground.opacity(0.05))
                
                Text(assignment != nil ? "#\(assignment!.kartNumber)" : "-")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(assignment != nil ? .kartAccent : .kartDim)
            }
            .frame(width: 56, height: 56)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment?.teamName ?? defaultName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.kartForeground)
                    .lineLimit(1)
                
                if let _ = assignment, (totalPenaltySeconds > 0 || penaltyCount > 0) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(penaltyCount) pen. | +\(totalPenaltySeconds)s")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                } else if assignment == nil {
                    Text("Nessun kart assegnato")
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                }
            }
            
            Spacer()
            
            // Buttons
            HStack(spacing: 8) {
                Button {
                    regToAssign = RegistrationSelection(id: id, defaultName: assignment?.teamName ?? defaultName)
                    assignKartNumberText = assignment != nil ? String(assignment!.kartNumber) : ""
                    assignKartNameText = assignment?.teamName ?? defaultName
                    showAssignAlert = true
                } label: {
                    Text(assignment != nil ? "Modifica" : "Assegna")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(10)
    }
    
    private func weightButton(weight: Double?, registrationId: Int) -> some View {
        Button {
            weightInputValue = weight != nil ? String(format: "%.1f", weight!) : ""
            weightAlertRegistrationId = registrationId
            showWeightAlert = true
        } label: {
            if let w = weight {
                Text(String(format: "%.1f kg", w))
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.kartForeground.opacity(0.1))
                    .foregroundColor(.kartForeground)
                    .cornerRadius(4)
            } else {
                HStack(spacing: 2) {
                    Image(systemName: "plus")
                    Text("Peso")
                }
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.kartDim.opacity(0.1))
                .foregroundColor(.kartDim)
                .cornerRadius(4)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var memberFallbackIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 14))
            .foregroundColor(.kartDim)
            .frame(width: 32, height: 32)
            .background(Color.kartForeground.opacity(0.06))
            .clipShape(Circle())
    }
}
