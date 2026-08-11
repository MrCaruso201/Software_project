import SwiftUI

/// Pannello per visualizzare i kart in pista e gestire le penalità
struct KartPenaltyView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var manager: KartTimingManager

    @State private var selectedKartNumber: Int? = nil
    @State private var selectedTeamName: String? = nil
    @State private var showPenaltySheet = false
    @State private var actionError: String? = nil
    
    @State private var showGenericMessageAlert = false
    @State private var genericMessageText = ""

    struct AvailableKart: Identifiable {
        let id = UUID()
        let kartNumber: Int
        let teamName: String?
    }

    var allAvailableKarts: [AvailableKart] {
        if let timing = manager.timing, !timing.rows.isEmpty {
            let h = timing.headers
            let kartIdx = h.firstIndex(where: { ["kart", "num", "n°", "no", "bib"].contains($0.lowercased()) })
            let nameIdx = h.firstIndex(where: { ["driver", "pilota", "name", "nome", "pilot"].contains($0.lowercased()) })
            
            var list: [AvailableKart] = []
            for row in timing.rows {
                if let kidx = kartIdx, row.indices.contains(kidx), let knum = Int(row[kidx]) {
                    let tname = (nameIdx != nil && row.indices.contains(nameIdx!)) ? row[nameIdx!] : nil
                    list.append(AvailableKart(kartNumber: knum, teamName: tname))
                }
            }
            if !list.isEmpty {
                return list.sorted { $0.kartNumber < $1.kartNumber }
            }
        }
        
        // Fallback agli assegnamenti
        return viewModel.kartAssignments.map { 
            AvailableKart(kartNumber: $0.kartNumber, teamName: $0.teamName) 
        }.sorted { $0.kartNumber < $1.kartNumber }
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    globalMessagesSection
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    
                    Spacer().frame(height: 14)

                    let available = allAvailableKarts
                    
                    if available.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "flag.2.crossed")
                                .font(.system(size: 44))
                                .foregroundColor(.kartDim.opacity(0.4))
                            Text("Nessun kart in pista")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.kartDim)
                        }
                        .padding(40)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                            ForEach(available) { kart in
                                Button(action: {
                                    selectedKartNumber = kart.kartNumber
                                    selectedTeamName = kart.teamName
                                    showPenaltySheet = true
                                }) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.kartPanel)
                                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07), lineWidth: 1))
                                            .aspectRatio(1, contentMode: .fill)
                                        
                                        VStack(spacing: 6) {
                                            Text("#\(kart.kartNumber)")
                                                .font(.system(size: 32, weight: .black, design: .monospaced))
                                                .foregroundColor(.kartAccent)
                                            
                                            let penaltyCount = viewModel.penaltiesByKart[kart.kartNumber]?.count ?? 0
                                            if penaltyCount > 0 {
                                                HStack(spacing: 2) {
                                                    Image(systemName: "exclamationmark.triangle.fill")
                                                    Text("\(penaltyCount)")
                                                }
                                                .font(.system(size: 11, weight: .bold))
                                                .foregroundColor(.orange)
                                            }
                                        }
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 30)
            }
        }
        .sheet(isPresented: $showPenaltySheet) {
            if let kartNumber = selectedKartNumber {
                PenaltySheetView(kartNumber: kartNumber, teamName: selectedTeamName, viewModel: viewModel)
            }
        }
        .alert("Messaggio Generico", isPresented: $showGenericMessageAlert) {
            TextField("Scrivi il messaggio...", text: $genericMessageText)
            Button("Invia") {
                sendGlobalMessage(.custom, text: genericMessageText)
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

    // MARK: - Pulsanti Globali

    private var globalMessagesSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            globalMessageButton(title: "Bandiera Gialla", icon: "flag.fill", color: .yellow, action: {
                sendGlobalMessage(.yellowFlag, text: "Bandiera Gialla")
            })
            globalMessageButton(title: "Bandiera Rossa", icon: "flag.fill", color: .red, action: {
                sendGlobalMessage(.redFlag, text: "Bandiera Rossa")
            })
            globalMessageButton(title: "Bandiera Verde", icon: "flag.fill", color: .green, action: {
                sendGlobalMessage(.greenFlag, text: "Bandiera Verde")
            })
            globalMessageButton(title: "Messaggio", icon: "bubble.left.and.bubble.right.fill", color: .blue, action: {
                genericMessageText = ""
                showGenericMessageAlert = true
            })
        }
    }

    private func globalMessageButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.8))
            .cornerRadius(12)
        }
    }

    private func sendGlobalMessage(_ type: MessagePreset, text: String) {
        Task {
            do {
                try await viewModel.sendMessage(targetKart: nil, type: type, text: text)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }
}


