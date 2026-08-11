import SwiftUI

/// Pannello Kart & Penalità per il Race Director.
/// Mostra tutti i kart assegnati all'evento con le rispettive penalità.
/// Permette di assegnare/rimuovere kart e aggiungere penalità.
struct KartPanelView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel

    @State private var showAssignSheet = false
    @State private var selectedKart: LiveKartAssignment? = nil
    @State private var showPenaltySheet = false
    @State private var actionError: String? = nil

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    // Header
                    HStack {
                        Text("\(viewModel.kartAssignments.count) kart in pista")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.kartDim)
                        Spacer()
                        Button(action: { showAssignSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                Text("Assegna Kart")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.kartAccent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                    if viewModel.kartAssignments.isEmpty {
                        emptyKarts
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            ForEach(viewModel.kartAssignments) { assignment in
                                KartCard(
                                    assignment: assignment,
                                    penaltyCount: viewModel.penaltiesByKart[assignment.kartNumber]?.count ?? 0,
                                    totalPenaltySeconds: viewModel.totalPenaltySeconds(for: assignment.kartNumber),
                                    onAddPenalty: {
                                        selectedKart = assignment
                                        showPenaltySheet = true
                                    },
                                    onRemove: {
                                        Task {
                                            do { try await viewModel.removeKart(kartNumber: assignment.kartNumber) }
                                            catch { actionError = error.localizedDescription }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)

                        // Dettaglio penalità per kart
                        if !viewModel.penalties.isEmpty {
                            penaltiesSection
                        }
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showAssignSheet) {
            AssignKartSheet(event: event, viewModel: viewModel)
        }
        .sheet(isPresented: $showPenaltySheet) {
            if let kart = selectedKart {
                PenaltySheetView(kartAssignment: kart, viewModel: viewModel)
            }
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

    // MARK: - Penalties Section

    private var penaltiesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
                Text("LOG PENALITÀ")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            ForEach(viewModel.penalties.reversed()) { penalty in
                PenaltyLogRow(penalty: penalty, onDelete: {
                    Task {
                        do { try await viewModel.deletePenalty(id: penalty.id) }
                        catch { actionError = error.localizedDescription }
                    }
                })
                .padding(.horizontal, 16)
            }
        }
    }

    private var emptyKarts: some View {
        VStack(spacing: 16) {
            Image(systemName: "flag.2.crossed")
                .font(.system(size: 44))
                .foregroundColor(.kartDim.opacity(0.4))
            Text("Nessun kart assegnato")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.kartDim)
            Text("Assegna un numero di kart a ogni squadra prima dell'inizio della gara.")
                .font(.system(size: 12))
                .foregroundColor(.kartDim.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Kart Card

struct KartCard: View {
    let assignment: LiveKartAssignment
    let penaltyCount: Int
    let totalPenaltySeconds: Int
    let onAddPenalty: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Numero Kart
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.kartAccent.opacity(0.12))
                VStack(spacing: 4) {
                    Text("#\(assignment.kartNumber)")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    Text(assignment.teamName ?? "Team")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.vertical, 14)
            }

            // Penalità badge
            if totalPenaltySeconds > 0 || penaltyCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("\(penaltyCount) pen. | +\(totalPenaltySeconds)s")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.08))
            }

            // Azioni
            HStack(spacing: 0) {
                Button(action: onAddPenalty) {
                    Label("Penalità", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.kartAccent.opacity(0.2))
                }
                Divider().background(Color.white.opacity(0.08)).frame(height: 32)
                Button(action: onRemove) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 40)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.08))
                }
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

// MARK: - Penalty Log Row

struct PenaltyLogRow: View {
    let penalty: RacePenalty
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(penalty.kartNumber)")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundColor(.kartAccent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(penalty.displayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                if let note = penalty.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                }
            }

            Spacer()

            if let date = penalty.parsedDate {
                Text(date, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.kartDim)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.6))
                    .font(.system(size: 16))
            }
        }
        .padding(12)
        .background(Color.kartPanel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Assign Kart Sheet

struct AssignKartSheet: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authState: AuthState

    @State private var selectedTeamId: String = ""
    @State private var selectedTeamName: String = ""
    @State private var kartNumberText: String = ""
    @State private var errorMsg: String? = nil
    @State private var isLoading = false

    // Team già assegnati
    private var assignedTeamIds: Set<String> {
        Set(viewModel.kartAssignments.map { $0.teamId })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                VStack(spacing: 20) {
                    // Kart number input
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NUMERO KART")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartAccent)
                        TextField("Es. 7", text: $kartNumberText)
                            .keyboardType(.numberPad)
                            .font(.system(size: 24, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.kartPanel)
                            .cornerRadius(12)
                    }

                    if let err = errorMsg {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Assegna Kart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }.foregroundColor(.kartDim)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Assegna") {
                        guard let num = Int(kartNumberText), !selectedTeamId.isEmpty else {
                            errorMsg = "Inserisci un numero kart valido e seleziona un team."
                            return
                        }
                        isLoading = true
                        Task {
                            do {
                                try await viewModel.assignKart(teamId: selectedTeamId, kartNumber: num, teamName: selectedTeamName)
                                dismiss()
                            } catch {
                                errorMsg = error.localizedDescription
                            }
                            isLoading = false
                        }
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.kartAccent)
                    .disabled(isLoading)
                }
            }
        }
    }
}
