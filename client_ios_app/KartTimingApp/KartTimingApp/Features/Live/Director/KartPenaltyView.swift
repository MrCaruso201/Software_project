import SwiftUI

/// Pannello unificato per messaggi broadcast e penalità kart
/// - In modalità "Broadcast": mostra i 4 pulsanti bandiera (visibili a tutti)
/// - In modalità "kart selezionato": mostra l'elenco di penalità/avvisi assegnabili
struct KartPenaltyView: View {
    let event: RaceEvent
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var manager: KartTimingManager
    @EnvironmentObject var authState: AuthState

    // Race control
    private var currentGlobalFlag: String? {
        let flagMessages = viewModel.messages.filter {
            $0.messageType == "yellow_flag" ||
            $0.messageType == "red_flag" ||
            $0.messageType == "green_flag" ||
            $0.messageType == "checkered_flag" ||
            ($0.messageType == "custom" && $0.text.lowercased() == "gara iniziata")
        }
        
        return flagMessages.sorted(by: {
            guard let d1 = $0.parsedDate, let d2 = $1.parsedDate else { return false }
            return d1 < d2
        }).last?.messageType
    }

    private var raceStatusColor: Color {
        guard event.status == "started" || event.status == "finished" else {
            return .gray
        }
        
        switch currentGlobalFlag {
        case "yellow_flag": return .yellow
        case "red_flag": return .red
        case "checkered_flag": return .white
        case "green_flag", "custom": return .kartGreen
        default: return .kartGreen
        }
    }

    // Selezione destinatario
    enum Target: Equatable {
        case broadcast
        case kart(Int, String?)  // (kartNumber, teamName)
    }

    @State private var selectedTarget: Target = .broadcast
    @State private var actionError: String? = nil
    
    // Penalità kart
    @State private var selectedType: PenaltyType? = nil
    @State private var seconds: String = ""
    @State private var note: String = ""
    @State private var isLoading = false
    @State private var penaltyError: String? = nil

    // Messaggio generico broadcast
    @State private var showGenericMessageAlert = false
    @State private var genericMessageText = ""
    
    @State private var showCheckeredFlagConfirm = false

    // Nota penalità kart
    @State private var showNoteInput = false

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
            if !list.isEmpty { return list.sorted { $0.kartNumber < $1.kartNumber } }
        }
        return viewModel.kartAssignments.map {
            AvailableKart(kartNumber: $0.kartNumber, teamName: $0.teamName)
        }.sorted { $0.kartNumber < $1.kartNumber }
    }

    var selectedKartNumber: Int? {
        if case .kart(let n, _) = selectedTarget { return n }
        return nil
    }

    var selectedTeamName: String? {
        if case .kart(_, let t) = selectedTarget { return t }
        return nil
    }

    private var isStarted:  Bool { event.status == "started" }
    private var isFinished: Bool { event.status == "finished" }
    private var isAdmin:    Bool { authState.currentUser?.role == .admin }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                raceControlSection

                targetPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)

                Divider().background(Color.white.opacity(0.06))

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTarget {
                        case .broadcast:
                            broadcastSection
                        case .kart:
                            kartPenaltySection
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
        .alert("Termina Gara", isPresented: $showCheckeredFlagConfirm) {
            Button("Termina", role: .destructive) {
                viewModel.raceEndTime = Date()
                sendGlobalMessage(.checkeredFlag, text: "Gara terminata. Rientrate ai box.")
            }
            Button("Annulla", role: .cancel) { }
        } message: {
            Text("Sei sicuro di voler terminare la gara?")
        }
        .alert("Messaggio", isPresented: $showGenericMessageAlert) {
            TextField("Scrivi il messaggio...", text: $genericMessageText)
            Button("Invia") { sendTargetedMessage(.custom, text: genericMessageText) }
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

        .onAppear {
            if selectedType == nil, let first = viewModel.penaltyTypes.first {
                selectedType = first
                if let defSec = first.defaultSeconds { seconds = String(defSec) }
            }
        }
    }

    // MARK: - Race Control Section

    /// Banner in cima alla schermata "Gestione LIVE" con il pulsante Avvia/Termina/Ripristina.
    private var raceControlSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONTROLLO GARA")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartDim)
                    Text(isStarted ? "In corso" : isFinished ? "Terminata" : "In attesa")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(isStarted ? .kartGreen : isFinished ? .kartDim : .white)
                }
                Spacer()

                RoundedRectangle(cornerRadius: 6)
                    .fill(raceStatusColor)
                    .frame(width: 44, height: 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kartPanel)
    }

    // MARK: - Target Picker (Menu a tendina)

    private var targetPicker: some View {
        Menu {
            Button {
                withAnimation { selectedTarget = .broadcast }
            } label: {
                Label("Broadcast (tutti)", systemImage: "antenna.radiowaves.left.and.right")
            }

            Divider()

            ForEach(allAvailableKarts) { kart in
                Button {
                    withAnimation {
                        selectedTarget = .kart(kart.kartNumber, kart.teamName)
                        // reset selezione tipo penalità
                        selectedType = viewModel.penaltyTypes.first
                        if let defSec = viewModel.penaltyTypes.first?.defaultSeconds {
                            seconds = String(defSec)
                        } else {
                            seconds = ""
                        }
                        note = ""
                        penaltyError = nil
                    }
                } label: {
                    Label("#\(kart.kartNumber)\(kart.teamName.map { " — \($0)" } ?? "")",
                          systemImage: "flag.fill")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Group {
                    switch selectedTarget {
                    case .broadcast:
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.kartAccent)
                    case .kart(let n, _):
                        Text("#\(n)")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.kartAccent)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(targetTitle)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text(targetSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                }

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.kartDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.kartPanel)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    private var targetTitle: String {
        switch selectedTarget {
        case .broadcast: return "Broadcast"
        case .kart(_, let name): return name ?? "Kart Selezionato"
        }
    }

    private var targetSubtitle: String {
        switch selectedTarget {
        case .broadcast: return "Messaggio a tutti i partecipanti"
        case .kart(let n, _): return "Assegna penalità al kart #\(n)"
        }
    }

    // MARK: - Sezione Broadcast

    private var broadcastSection: some View {
        VStack(spacing: 12) {
            sectionHeader(text: "MESSAGGIO GLOBALE", icon: "antenna.radiowaves.left.and.right")

            // Griglia 2x2 bandiere
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                globalMessageButton(title: "Bandiera Gialla", icon: "flag.fill", color: .yellow) {
                    sendGlobalMessage(.yellowFlag, text: "Bandiera Gialla")
                }
                globalMessageButton(title: "Bandiera Rossa", icon: "flag.fill", color: .red) {
                    sendGlobalMessage(.redFlag, text: "Bandiera Rossa")
                }
                globalMessageButton(title: "Bandiera Verde", icon: "flag.fill", color: .green) {
                    sendGlobalMessage(.greenFlag, text: "Bandiera Verde")
                }
                if viewModel.raceStartTime == nil || viewModel.raceEndTime != nil || currentGlobalFlag == "red_flag" {
                    globalMessageButton(title: "Inizia Gara", icon: "play.fill", color: .green) {
                        viewModel.raceStartTime = Date()
                        viewModel.raceEndTime = nil
                        sendGlobalMessage(.custom, text: "Gara Iniziata")
                    }
                } else {
                    globalMessageButton(title: "Bandiera a Scacchi", icon: "flag.checkered.2.crossed", color: Color(white: 0.85)) {
                        showCheckeredFlagConfirm = true
                    }
                }
            }

            // Messaggio generico — larghezza piena, posizione finale
            globalMessageButton(title: "Messaggio Generico", icon: "bubble.left.and.bubble.right.fill", color: .blue) {
                genericMessageText = ""
                showGenericMessageAlert = true
            }

            // Bandiere Nere attive
            let blackFlags = viewModel.penalties.filter { $0.penaltyType == "black_flag" }
            if !blackFlags.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("BANDIERE NERE ATTIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.red)
                        .padding(.top, 16)
                    
                    ForEach(blackFlags) { pen in
                        PenaltyLogRow(penalty: pen, onDelete: {
                            Task {
                                do { try await viewModel.deletePenalty(id: pen.id) }
                                catch { actionError = error.localizedDescription }
                            }
                        })
                    }
                }
            }
        }
    }

    // MARK: - Sezione Penalità Kart

    private var kartPenaltySection: some View {
        VStack(spacing: 16) {
            // Header kart
            if case .kart(let n, let name) = selectedTarget {
                HStack(spacing: 12) {
                    Text("#\(n)")
                        .font(.system(size: 40, weight: .black, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name ?? "Team Sconosciuto")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        // Penalità attive
                        let penCount = viewModel.penaltiesByKart[n]?.filter { !$0.isWarning }.count ?? 0
                        let warnCount = viewModel.penaltiesByKart[n]?.filter { $0.isWarning }.count ?? 0
                        HStack(spacing: 8) {
                            if penCount > 0 {
                                Label("\(penCount) pen.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.yellow)
                            }
                            if warnCount > 0 {
                                Label("\(warnCount) avv.", systemImage: "exclamationmark.bubble.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.kartDim)
                            }
                            if penCount == 0 && warnCount == 0 {
                                Text("Nessuna sanzione")
                                    .font(.system(size: 11))
                                    .foregroundColor(.kartDim)
                            }
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.kartPanel)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.kartAccent.opacity(0.2), lineWidth: 1))
            }

            sectionHeader(text: "SELEZIONA SANZIONE", icon: "flag.fill")

            // Griglia tipi penalità ordinata: penalità → avvisi → personalizzata/generico
            if viewModel.penaltyTypes.isEmpty {
                Text("Caricamento tipi penalità...")
                    .font(.system(size: 13))
                    .foregroundColor(.kartDim)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                let ordered = sortedPenaltyTypes
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(ordered) { pType in
                        penaltyTypeButton(pType)
                    }
                }
            }

            // Campo secondi solo per tipi personalizzabili
            if let sel = selectedType, sel.requiresSeconds {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SECONDI DI PENALITÀ")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    TextField("Es. 10", text: $seconds)
                        .keyboardType(.numberPad)
                        .font(.system(size: 24, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.kartPanel)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartAccent.opacity(0.3), lineWidth: 1))
                }
            }

            // Nota opzionale solo per tipi personalizzabili
            if let sel = selectedType, sel.isCustomizable {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTA (OPZIONALE)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartDim)
                    TextField("Descrizione aggiuntiva...", text: $note)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.kartPanel)
                        .cornerRadius(12)
                }
            }

            if let err = penaltyError {
                Text(err).font(.system(size: 12)).foregroundColor(.red)
            }

            // Bottone conferma
            Button(action: confirmPenalty) {
                HStack {
                    if isLoading {
                        ProgressView().tint(.black).scaleEffect(0.8)
                    } else {
                        Image(systemName: selectedType?.systemIcon ?? "exclamationmark.triangle.fill")
                        Text("Assegna \"\(selectedType?.name ?? "Sanzione")\"")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.kartAccent)
                .cornerRadius(14)
            }
            .disabled(isLoading || selectedType == nil)

            Divider().background(Color.white.opacity(0.1))
                .padding(.vertical, 8)

            // Bottone Messaggio
            if case .kart(let n, _) = selectedTarget {
                globalMessageButton(title: "Invia Messaggio al Kart #\(n)", icon: "envelope.fill", color: .blue) {
                    genericMessageText = ""
                    showGenericMessageAlert = true
                }
            }
        }
    }

    /// Ordine: penalità fisse → avvisi → bandiera nera → bandiera blu → penalità personalizzata → avviso generico
    private var sortedPenaltyTypes: [PenaltyType] {
        let types = viewModel.penaltyTypes

        // 1. Penalità fisse (non warning, non custom, non bandiere)
        let fixedPenalties = types.filter {
            !$0.isWarning && !$0.isCustomizable
            && $0.code != "black_flag" && $0.code != "blue_flag"
        }.sorted { $0.id < $1.id }

        // 2. Avvisi con auto-penalty (warning_track_limits, warning_aggressive_driving)
        let autoWarnings = types.filter {
            $0.isWarning && $0.warningThreshold != nil
            && $0.code != "drop_position"
        }.sorted { $0.id < $1.id }

        // 3. Bandiera nera
        let blackFlag = types.filter { $0.code == "black_flag" }

        // 4. Bandiera blu
        let blueFlag = types.filter { $0.code == "blue_flag" }

        // 5. Penalità personalizzata
        let custom = types.filter { $0.code == "custom" }

        // 6. Avviso generico
        let genericWarn = types.filter { $0.code == "drop_position" }

        return fixedPenalties + autoWarnings + blackFlag + blueFlag + custom + genericWarn
    }

    // MARK: - Sub-views

    private func penaltyTypeButton(_ pType: PenaltyType) -> some View {
        let isSelected = selectedType?.id == pType.id
        
        let accentCol: Color = {
            switch pType.code {
            case "black_flag": return .red
            case "blue_flag": return .blue
            case "custom": return .purple
            case "drop_position": return .orange
            default:
                return pType.isWarning ? .kartDim : .yellow
            }
        }()

        return Button(action: {
            withAnimation(.spring(response: 0.25)) {
                selectedType = pType
                // Pre-popola i secondi solo se c'è un valore di default
                if let defSec = pType.defaultSeconds {
                    seconds = String(defSec)
                } else {
                    seconds = ""
                }
                penaltyError = nil
            }
        }) {
            VStack(spacing: 8) {
                // Icona / tempo
                if !pType.isWarning && !pType.isCustomizable, let defSec = pType.defaultSeconds {
                    // Penalità fissa con tempo noto → mostra il tempo
                    Text("+\(defSec)s")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(isSelected ? .white : accentCol)
                } else {
                    Image(systemName: pType.systemIcon)
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? .white : accentCol)
                }
                Text(pType.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(isSelected ? .white : .white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let threshold = pType.warningThreshold {
                    Text("Auto dopo \(threshold)x")
                        .font(.system(size: 9))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : accentCol.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            .background(isSelected ? accentCol : accentCol.opacity(0.15))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? accentCol : accentCol.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25), value: isSelected)
    }

    private func globalMessageButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 24))
                Text(title).font(.system(size: 13, weight: .bold)).multilineTextAlignment(.center)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color.opacity(0.82))
            .cornerRadius(12)
        }
    }

    private func sectionHeader(text: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.kartAccent)
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.kartAccent)
            Spacer()
        }
    }

    // MARK: - Actions

    private func sendGlobalMessage(_ type: MessagePreset, text: String) {
        Task {
            do {
                try await viewModel.sendMessage(targetKart: nil, type: type, text: text)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func sendTargetedMessage(_ type: MessagePreset, text: String) {
        Task {
            do {
                let targetNum: Int?
                if case .kart(let n, _) = selectedTarget {
                    targetNum = n
                } else {
                    targetNum = nil
                }
                try await viewModel.sendMessage(targetKart: targetNum, type: type, text: text)
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    private func confirmPenalty() {
        guard let selected = selectedType else {
            penaltyError = "Seleziona un tipo di penalità."
            return
        }
        guard case .kart(let kartNumber, _) = selectedTarget else { return }

        let sec: Int? = selected.requiresSeconds ? Int(seconds) : nil
        if selected.requiresSeconds && sec == nil {
            penaltyError = "Inserisci un numero di secondi valido."
            return
        }
        isLoading = true
        penaltyError = nil
        Task {
            do {
                try await viewModel.addPenalty(
                    kartNumber: kartNumber,
                    type: selected,
                    seconds: sec,
                    note: note.isEmpty ? nil : note
                )
                // Reset dopo successo
                note = ""
                if let defSec = selected.defaultSeconds { seconds = String(defSec) }
            } catch {
                penaltyError = error.localizedDescription
            }
            isLoading = false
        }
    }
}
