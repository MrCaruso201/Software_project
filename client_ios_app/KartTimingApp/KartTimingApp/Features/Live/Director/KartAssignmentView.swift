import SwiftUI

/// Pannello per assegnare i kart alle squadre iscritte
struct KartAssignmentView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var manager: KartTimingManager

    struct TeamSelection: Identifiable {
        let id: String
        let name: String
    }

    @State private var teamToAssign: TeamSelection? = nil
    @State private var showAssignAlert = false
    @State private var assignKartNumberText = ""
    @State private var actionError: String? = nil

    // Combina i team iscritti e gli assegnamenti orfani
    var combinedList: [TeamItem] {
        var items: [TeamItem] = []
        var processedTeamIds = Set<String>()
        
        // 1. Team Iscritti
        for team in viewModel.registeredTeams {
            let match = viewModel.kartAssignments.first(where: { $0.teamId == team.teamId })
            items.append(TeamItem(id: team.teamId, name: team.teamName, assignment: match))
            processedTeamIds.insert(team.teamId)
        }
        
        // 2. Orfani
        for kart in viewModel.kartAssignments {
            let effTeamId = kart.teamId.isEmpty ? UUID().uuidString : kart.teamId
            if !processedTeamIds.contains(effTeamId) {
                items.append(TeamItem(id: effTeamId, name: kart.teamName ?? "Sconosciuto", assignment: kart))
                if !kart.teamId.isEmpty {
                    processedTeamIds.insert(effTeamId)
                }
            }
        }
        
        return items
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    HStack {
                        Text("\(viewModel.kartAssignments.count) kart assegnati su \(combinedList.count) squadre")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.kartDim)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    if combinedList.isEmpty {
                        emptyKarts
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(combinedList) { item in
                                KartRow(
                                    teamName: item.name,
                                    assignment: item.assignment,
                                    penaltyCount: item.assignment != nil ? (viewModel.penaltiesByKart[item.assignment!.kartNumber]?.filter { !$0.isWarning }.count ?? 0) : 0,
                                    totalPenaltySeconds: item.assignment != nil ? viewModel.totalPenaltySeconds(for: item.assignment!.kartNumber) : 0,
                                    onTap: {
                                        teamToAssign = TeamSelection(id: item.id, name: item.name)
                                        assignKartNumberText = item.assignment != nil ? String(item.assignment!.kartNumber) : ""
                                        showAssignAlert = true
                                    },
                                    onRemove: {
                                        if let kart = item.assignment {
                                            Task {
                                                do { try await viewModel.removeKart(kartNumber: kart.kartNumber) }
                                                catch { actionError = error.localizedDescription }
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .alert("Assegna Kart a \(teamToAssign?.name ?? "")", isPresented: $showAssignAlert) {
            TextField("Numero Kart", text: $assignKartNumberText)
                .keyboardType(.numberPad)
            Button("Assegna") {
                guard let num = Int(assignKartNumberText), let team = teamToAssign else { return }
                Task {
                    do {
                        try await viewModel.assignKart(teamId: team.id, kartNumber: num, teamName: team.name)
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
            Button("Annulla", role: .cancel) { }
        }
        .alert("Errore", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var emptyKarts: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.2.crossed")
                .font(.system(size: 44))
                .foregroundColor(.kartDim.opacity(0.4))
            Text("Nessuna squadra iscritta")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.kartDim)
            Text("Le squadre iscritte all'evento appariranno qui.")
                .font(.system(size: 12))
                .foregroundColor(.kartDim.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

struct TeamItem: Identifiable {
    let id: String
    let name: String
    let assignment: LiveKartAssignment?
}

// MARK: - Kart Card

struct KartRow: View {
    let teamName: String
    let assignment: LiveKartAssignment?
    let penaltyCount: Int
    let totalPenaltySeconds: Int
    let onTap: () -> Void
    let onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            // Area cliccabile: Numero e Nome
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Numero Kart (colonna piccola)
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(assignment != nil ? Color.kartAccent.opacity(0.12) : Color.white.opacity(0.05))
                        
                        Text(assignment != nil ? "#\(assignment!.kartNumber)" : "-")
                            .font(.system(size: 20, weight: .black, design: .monospaced))
                            .foregroundColor(assignment != nil ? .kartAccent : .kartDim)
                    }
                    .frame(width: 56, height: 56)
                    
                    // Nome Squadra e badge penalità
                    VStack(alignment: .leading, spacing: 4) {
                        Text(teamName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        if let _ = assignment, (totalPenaltySeconds > 0 || penaltyCount > 0) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("\(penaltyCount) pen. | +\(totalPenaltySeconds)s")
                            }
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.orange)
                        } else if assignment == nil {
                            Text("Tocca per assegnare un kart")
                                .font(.system(size: 11))
                                .foregroundColor(.kartDim)
                        }
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            Spacer()
            
            // Azioni
            if assignment != nil {
                HStack(spacing: 8) {
                    if let onRemove = onRemove {
                        Button(action: onRemove) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 38, height: 38)
                                .background(Color.red.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .padding(10)
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}
