import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Vista Classifica Live per il Race Director.
/// Mostra la classifica proveniente dal WebSocket,
/// con badge per le penalità totali di ogni kart.
struct ClassificaLiveView: View {
    var isDirector: Bool = false
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var manager: KartTimingManager

    /// Binding settato a `true` dal parent (DirectorLiveView) per triggerare l'export.
    @Binding var exportRequested: Bool

    @State private var expandedDriverId: String? = nil

    // CSV export
    @State private var showShareSheet = false
    @State private var csvExportURL: URL? = nil

    // Upload CSV
    @State private var showFileImporter = false
    @State private var isUploadingResults = false
    @State private var uploadError: String? = nil
    @State private var selectedFileURL: URL? = nil
    
    // Session Naming
    @State private var editingSessionName: String = ""
    @State private var isSavingSessionName = false
    
    @State private var viewMode: String = "live" // "live", "qualifying", "final", ...
    
    // Custom Tabs
    @State private var showAddTabAlert = false
    @State private var newTabName = ""
    @State private var customTabs: [String] = []
    @State private var showDeleteTabAlert = false
    @State private var isDeletingTab = false
    
    private var extraTabs: [String] {
        let resultsTypes: [String] = viewModel.eventResults.compactMap { $0.resultType }
        let allTypes: [String] = resultsTypes + customTabs
        let uniqueTypes: Set<String> = Set(allTypes)
        return uniqueTypes.filter { !$0.isEmpty && $0 != "qualifying" && $0 != "final" && $0 != "live" }.sorted()
    }
    
    /// True se la tab corrente è una extra tab eliminabile (non built-in)
    private var isCurrentTabDeletable: Bool {
        extraTabs.contains(viewMode)
    }
    
    private var currentLabelText: String {
        if viewMode == "live" { return "Live Timing" }
        if viewMode == "qualifying" { return "Qualifica (Griglia)" }
        if viewMode == "final" { return "Classifica Finale" }
        return viewMode.capitalized
    }
    
    private var lastFlagMessage: RaceMessage? {
        viewModel.messages.filter {
            $0.messageType == "yellow_flag" ||
            $0.messageType == "red_flag" ||
            $0.messageType == "green_flag" ||
            $0.messageType == "checkered_flag" ||
            ($0.messageType == "custom" && $0.text.lowercased() == "gara iniziata")
        }.sorted(by: {
            guard let d1 = $0.parsedDate, let d2 = $1.parsedDate else { return false }
            return d1 < d2
        }).last
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                sessionNameBanner
                
                // Status bar
                statusBar

                Menu {
                    Button(action: { viewMode = "live" }) {
                        Label("Live Timing", systemImage: "timer")
                    }
                    Button(action: { viewMode = "qualifying" }) {
                        Label("Qualifica (Griglia)", systemImage: "flag.checkered")
                    }
                    Button(action: { viewMode = "final" }) {
                        Label("Classifica Finale", systemImage: "list.number")
                    }
                    
                    if !extraTabs.isEmpty {
                        Divider()
                        ForEach(extraTabs, id: \.self) { tab in
                            Button(action: { viewMode = tab }) {
                                Label(tab.capitalized, systemImage: "doc.text")
                            }
                        }
                    }
                    
                    if isDirector {
                        Divider()
                        Button(action: { showAddTabAlert = true }) {
                            Label("Aggiungi nuova tab...", systemImage: "plus")
                        }
                    }
                } label: {
                    HStack {
                        Text(currentLabelText)
                            .font(.system(size: 16, weight: .bold))
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.kartPanel)
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                if isDirector && viewMode != "live" {
                    HStack(spacing: 12) {
                        Button(action: { showFileImporter = true }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("Carica CSV")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.kartAccent)
                            .cornerRadius(8)
                        }
                        
                        Button(action: {
                            Task {
                                do {
                                    try await viewModel.deleteResultsCSV(resultType: viewMode)
                                } catch {
                                    uploadError = error.localizedDescription
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Cancella CSV")
                            }
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.7))
                            .cornerRadius(8)
                        }
                        
                        // Elimina l'intera tab (solo per tab extra, non per quelle built-in)
                        if isCurrentTabDeletable {
                            Spacer()
                            Button(action: { showDeleteTabAlert = true }) {
                                HStack(spacing: 6) {
                                    if isDeletingTab {
                                        ProgressView().scaleEffect(0.7).tint(.white)
                                    } else {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    Text(isDeletingTab ? "Eliminazione..." : "Elimina Tab")
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.red)
                                .cornerRadius(8)
                            }
                            .disabled(isDeletingTab)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.kartPanel)
                }

                if viewMode != "live" && viewModel.eventResults.contains(where: { $0.resultType == viewMode }) {
                    staticResultsView()
                } else if viewMode != "live" {
                    VStack {
                        Spacer()
                        Text("Nessun risultato caricato per questa modalità.")
                            .foregroundColor(.kartDim)
                            .font(.system(size: 14))
                        Spacer()
                    }
                } else if let timing = manager.timing, !timing.rows.isEmpty {
                    timingTable(timing: timing)
                } else {
                    emptyState
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = csvExportURL {
                ShareSheet(items: [url])
            }
        }
        .onChange(of: exportRequested) { oldValue, newValue in
            guard newValue else { return }
            exportRequested = false
            csvExportURL = buildCSV()
            if csvExportURL != nil { showShareSheet = true }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case .success(let url):
                self.selectedFileURL = url
                Task { await handleCSVUpload(type: viewMode) }
            case .failure(let error):
                self.uploadError = error.localizedDescription
            }
        }
        .alert("Errore", isPresented: .constant(uploadError != nil)) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        .alert("Nuova Tab", isPresented: $showAddTabAlert) {
            TextField("Nome (es. Prove Libere)", text: $newTabName)
            Button("Annulla", role: .cancel) { newTabName = "" }
            Button("Aggiungi") {
                let trimmed = newTabName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if !customTabs.contains(trimmed) {
                        customTabs.append(trimmed)
                    }
                    viewMode = trimmed
                }
                newTabName = ""
            }
        } message: {
            Text("Inserisci il nome per la nuova classifica.")
        }
        .alert("Elimina tab", isPresented: $showDeleteTabAlert) {
            Button("Annulla", role: .cancel) { }
            Button("Elimina", role: .destructive) {
                deleteCurrentTab()
            }
        } message: {
            Text("Vuoi eliminare la tab \"\(viewMode.capitalized)\" e il suo CSV? L'operazione non è reversibile.")
        }
        .onChange(of: viewModel.currentSessionName) { _, new in
            if !isSavingSessionName {
                self.editingSessionName = new ?? ""
            }
        }
    }

    private func handleCSVUpload(type: String) async {
        guard let url = selectedFileURL else { return }
        isUploadingResults = true
        do {
            _ = try await viewModel.uploadResultsCSV(fileURL: url, resultType: type)
            self.viewMode = type // Switch to static results view automatically
        } catch {
            self.uploadError = error.localizedDescription
        }
        isUploadingResults = false
        selectedFileURL = nil
    }
    
    private func deleteCurrentTab() {
        let tabToDelete = viewMode
        Task {
            isDeletingTab = true
            // Cancella il CSV dal server se esiste
            if viewModel.eventResults.contains(where: { $0.resultType == tabToDelete }) {
                try? await viewModel.deleteResultsCSV(resultType: tabToDelete)
            }
            // Rimuove dalla lista locale delle custom tabs
            customTabs.removeAll { $0 == tabToDelete }
            // Torna alla tab live
            viewMode = "live"
            isDeletingTab = false
        }
    }



    // ── Session Banner ──────────────────────────────────────────────────────

    private var sessionNameBanner: some View {
        HStack(spacing: 8) {
            if isDirector {
                TextField("Nome Turno (es. Gara 1)", text: $editingSessionName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .onSubmit {
                        saveSessionName()
                    }
                
                // Pulsante salva esplicito (evita dipendenza dal tasto Invio)
                Button {
                    saveSessionName()
                } label: {
                    if isSavingSessionName {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.kartAccent)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.kartAccent)
                    }
                }
                .disabled(isSavingSessionName)
            } else if let sessionName = viewModel.currentSessionName, !sessionName.isEmpty {
                Text(sessionName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
    }
    
    private func saveSessionName() {
        Task {
            isSavingSessionName = true
            try? await viewModel.updateEventStatus(sessionName: editingSessionName)
            isSavingSessionName = false
        }
    }

    // ── Risultati Statici (Griglia o Classifica Finale) ───────────────────

    @ViewBuilder
    private func staticResultsView() -> some View {
        let results = viewModel.eventResults
            .filter { $0.resultType == viewMode }
            .sorted { ($0.position ?? 999) < ($1.position ?? 999) }
        
        VStack(spacing: 0) {
            HStack {
                Text(viewMode == "qualifying" ? "GRIGLIA DI PARTENZA" : "RISULTATI (\(viewMode.uppercased()))")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
            }
            .padding()
            .background(Color.kartPanel)
            
            ScrollView {
                if viewMode == "qualifying" {
                    // F1 Style Grid with inverted U
                    VStack(spacing: 16) {
                        ForEach(results) { res in
                            let isRight = (res.position ?? 1) % 2 == 0
                            HStack {
                                if isRight { Spacer(minLength: 60) }
                                
                                VStack(spacing: 4) {
                                    let bestStr = res.formattedBestLap ?? ""
                                    let nameText = bestStr.isEmpty ? res.displayName : "\(res.displayName) - \(bestStr)"
                                    Text(nameText)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        
                                    Text("\(res.position ?? 0)")
                                        .font(.system(size: 24, weight: .black, design: .monospaced))
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(Color.kartPanel)
                                        .overlay(
                                            InvertedUShape().stroke(Color.white, lineWidth: 3)
                                        )
                                }
                                .padding()
                                
                                if !isRight { Spacer(minLength: 60) }
                            }
                        }
                    }
                    .padding()
                } else {
                    // List format for final results
                    VStack(spacing: 8) {
                        ForEach(results) { res in
                            staticResultCard(res: res)
                        }
                    }
                    .padding()
                }
            }
        }
    }

    private func staticResultCard(res: EventResult) -> some View {
        let pos = res.position ?? 0
        let isFirst = pos == 1
        let isSecond = pos == 2
        let isThird = pos == 3
        
        let positionColor: Color = {
            if isFirst { return Color(red: 1.0, green: 0.84, blue: 0.0) } // Gold
            if isSecond { return Color(white: 0.75) } // Silver
            if isThird { return Color(red: 0.8, green: 0.5, blue: 0.2) } // Bronze
            return .kartDim
        }()
        
        let borderColor = (isFirst || isSecond || isThird) ? positionColor.opacity(0.4) : Color.white.opacity(0.1)
        
        return HStack(spacing: 16) {
            // Posizione
            Group {
                if isFirst || isSecond || isThird {
                    ZStack {
                        Circle()
                            .strokeBorder(positionColor.opacity(0.5), lineWidth: 1)
                            .background(Circle().fill(positionColor.opacity(0.15)))
                            .frame(width: 44, height: 44)
                        Text("\(pos)°")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(positionColor)
                    }
                    .frame(width: 50)
                } else {
                    Text("\(pos)°")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(positionColor)
                        .frame(width: 50, alignment: .center)
                }
            }
            
            // Info pilota e tempi
            VStack(alignment: .leading, spacing: 6) {
                // Nome e numero
                HStack(spacing: 8) {
                    if let kartNum = res.kartNumber {
                        Text("#\(kartNum)")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.kartDim)
                    
                    Text(res.displayName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                
                // Tempi e Gap
                HStack(spacing: 12) {
                    if let best = res.formattedBestLap {
                        HStack(spacing: 4) {
                            Image(systemName: "stopwatch")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                            Text(best)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.red)
                        }
                    }
                    if let gap = res.gap {
                        let isLeader = gap.lowercased() == "leader"
                        Text(gap)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(isLeader ? .red : .kartDim)
                    }
                }
            }
            
            Spacer()
            
            // Giri
            if let laps = res.laps {
                VStack(spacing: 2) {
                    Text("\(laps)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    Text("Giri")
                        .font(.system(size: 10))
                        .foregroundColor(.kartDim)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    // ── Status bar ────────────────────────────────────────────────────────

    private var statusBar: some View {
        HStack(spacing: 10) {
            // Connessione
            HStack(spacing: 5) {
                Circle()
                    .fill(manager.isConnected ? Color.kartGreen : Color.kartRed)
                    .frame(width: 7, height: 7)
                Text(manager.isConnected ? "Connesso WS" : "Disconnesso WS")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(manager.isConnected ? .kartGreen : .kartRed)
            }

            Spacer()

            // Scraping live
            if manager.isScrapingActive {
                HStack(spacing: 4) {
                    Circle().fill(Color.kartAccent).frame(width: 5, height: 5)
                        .opacity(manager.timing != nil ? 1 : 0.4)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.kartAccent)
                }
            }

            // Ultimo aggiornamento
            if let timing = manager.timing {
                Text(shortTime(timing.updatedAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
        }
        .overlay(
            Group {
                if let startTime = viewModel.raceStartTime {
                    TimelineView(.periodic(from: startTime, by: 1.0)) { context in
                        let flag = lastFlagMessage
                        let isRedFlag = flag?.messageType == "red_flag"
                        
                        let targetDate = viewModel.raceEndTime ?? (isRedFlag ? (flag?.parsedDate ?? context.date) : context.date)
                        
                        let elapsed = max(0, targetDate.timeIntervalSince(startTime))
                        let min = Int(elapsed) / 60
                        let sec = Int(elapsed) % 60
                        
                        HStack(spacing: 6) {
                            if viewModel.raceEndTime != nil || flag?.messageType == "checkered_flag" {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            } else if let type = flag?.messageType {
                                switch type {
                                case "yellow_flag":
                                    RoundedRectangle(cornerRadius: 3).fill(Color.yellow).frame(width: 14, height: 14)
                                case "red_flag":
                                    RoundedRectangle(cornerRadius: 3).fill(Color.red).frame(width: 14, height: 14)
                                case "green_flag", "custom":
                                    RoundedRectangle(cornerRadius: 3).fill(Color.kartGreen).frame(width: 14, height: 14)
                                default:
                                    EmptyView()
                                }
                            }
                            
                            Text(String(format: (viewModel.raceEndTime != nil || flag?.messageType == "checkered_flag") ? "%02d:%02d" : "T: %02d:%02d", min, sec))
                                .font(.system(size: 16, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                    }
                } else {
                    Text("T: 00:00")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kartPanel)
    }

    // ── Tabella classifica ────────────────────────────────────────────────

    private func colIndex(in headers: [String], keywords: [String]) -> Int? {
        for kw in keywords {
            if let i = headers.firstIndex(where: { $0.lowercased().contains(kw) }) {
                return i
            }
        }
        return nil
    }

    private func abbrev(_ name: String) -> String {
        let letters = name.filter { $0.isLetter }
        return String(letters.prefix(3)).uppercased()
    }

    @ViewBuilder
    private func timingTable(timing: TimingPayload) -> some View {
        let h = timing.headers
        let posIdx  = colIndex(in: h, keywords: ["pos", "pos.", "p", "#"])           ?? 0
        let kartIdx = colIndex(in: h, keywords: ["kart", "num", "n°", "no", "bib"])
        let nameIdx = colIndex(in: h, keywords: ["driver", "pilota", "name", "nome", "pilot"])
        let lapIdx  = colIndex(in: h, keywords: ["last", "lap", "giro", "time", "tempo"])
        let gapIdx  = colIndex(in: h, keywords: ["gap", "diff", "distanza", "behind"])
        let bestIdx = colIndex(in: h, keywords: ["best", "migliore", "fastest", "record"])

        let primarySet: Set<Int> = [posIdx, kartIdx, nameIdx, lapIdx, gapIdx, bestIdx]
            .compactMap { $0 }
            .reduce(into: Set<Int>()) { $0.insert($1) }

        ScrollView {
            VStack(spacing: 6) {
                ForEach(Array(timing.rows.enumerated()), id: \.offset) { idx, row in
                    kartCard(
                        row: row,
                        headers: h,
                        index: idx,
                        posIdx: posIdx,
                        kartIdx: kartIdx,
                        nameIdx: nameIdx,
                        lapIdx: lapIdx,
                        gapIdx: gapIdx,
                        bestIdx: bestIdx,
                        primarySet: primarySet
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func kartCard(
        row: [String],
        headers: [String],
        index: Int,
        posIdx: Int,
        kartIdx: Int?,
        nameIdx: Int?,
        lapIdx: Int?,
        gapIdx: Int?,
        bestIdx: Int?,
        primarySet: Set<Int>
    ) -> some View {
        let pos      = row.indices.contains(posIdx)  ? row[posIdx]  : "-"
        let kart     = kartIdx.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
        let fullName = nameIdx.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
        let lapTime  = lapIdx.flatMap  { row.indices.contains($0) ? row[$0] : nil } ?? "-"
        let gap      = gapIdx.flatMap  { row.indices.contains($0) ? row[$0] : nil } ?? ""
        let best     = bestIdx.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""

        let isLeader = (pos == "1")
        let shortName = abbrev(fullName)
        
        let driverId = fullName.isEmpty ? "kart-\(kart)" : fullName
        let isExpanded = (expandedDriverId == driverId)

        let extras: [(String, String)] = headers.indices.compactMap { i in
            guard !primarySet.contains(i),
                  row.indices.contains(i),
                  !row[i].trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return (headers[i], row[i])
        }

        // Penalties extraction from LiveViewModel
        let parsedKart = Int(kart) ?? -1
        let kartPenaltiesList = parsedKart > 0 ? (viewModel.penaltiesByKart[parsedKart] ?? []) : []
        let actualPenaltiesCount = kartPenaltiesList.filter { !$0.isWarning }.count
        let totalCount = kartPenaltiesList.count
        let totalSec = parsedKart > 0 ? viewModel.totalPenaltySeconds(for: parsedKart) : 0
        let hasBlackFlag = kartPenaltiesList.contains(where: { $0.penaltyType == "black_flag" })

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(hasBlackFlag ? Color.red.opacity(0.2) : (isLeader
                      ? Color.kartAccent.opacity(0.12)
                      : Color.kartPanel))

            if isLeader {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.kartAccent.opacity(0.5), lineWidth: 1)
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {

                    // ── Posizione ──────────────────────────────────────────
                    Text(pos)
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundColor(isLeader ? .kartAccent : .kartDim)
                        .frame(width: 44)

                    // Divisore
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 1, height: 44)

                    // ── Kart # + Nome ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if !kart.isEmpty {
                                Text("#\(kart)")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            if !shortName.isEmpty {
                                Text(shortName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(isLeader ? .kartAccent : .white)
                                    .tracking(2)
                            }
                            
                            // Badges Penalità
                            if hasBlackFlag {
                                Text("DSQ")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.red)
                                    .cornerRadius(4)
                                    .padding(.leading, 4)
                            } else if actualPenaltiesCount > 0 {
                                HStack(spacing: 4) {
                                    Text("+\(totalSec)s")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.orange)
                                        .cornerRadius(4)
                                }
                                .padding(.leading, 4)
                            }
                        }

                        // Extra secondari
                        if !extras.isEmpty {
                            Text(extras.map { "\($0.0.prefix(4).uppercased()):\($0.1)" }.joined(separator: "  "))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.kartDim)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)

                    // ── Tempi ──────────────────────────────────────────────
                    VStack(alignment: .trailing, spacing: 3) {
                        // Ultimo giro
                        Text(lapTime)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundColor(isLeader ? .kartAccent : .white)

                        HStack(spacing: 8) {
                            // Migliore giro
                            if !best.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 7))
                                        .foregroundColor(.kartGreen)
                                    Text(best)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.kartGreen)
                                }
                            }
                            // Gap
                            if !gap.isEmpty && !isLeader {
                                Text(gap)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.kartDim)
                            }
                        }
                    }
                    .padding(.trailing, 12)
                    
                    // Chevron
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.kartDim)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.trailing, 12)
                }
                .padding(.vertical, 10)
                
                if isExpanded {
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 14) {
                        if !fullName.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PILOTA / SQUADRA")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.kartDim)
                                Text(fullName)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        let allDetails: [(index: Int, header: String, value: String)] = headers.indices.compactMap { i in
                            guard row.indices.contains(i) else { return nil }
                            let val = row[i].trimmingCharacters(in: .whitespaces)
                            return (index: i, header: headers[i], value: val)
                        }
                        
                        let gridItems = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                        
                        LazyVGrid(columns: gridItems, alignment: .leading, spacing: 12) {
                            ForEach(allDetails, id: \.index) { item in
                                if !["driver", "pilota", "name", "nome", "pilot"].contains(item.header.lowercased()) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.header.uppercased())
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.kartDim)
                                        Text(item.value)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        
                        if totalCount > 0 {
                            let kartPenalties = viewModel.penaltiesByKart[parsedKart] ?? []
                            let actualPenalties = kartPenalties.filter { !$0.isWarning }
                            let warnings = kartPenalties.filter { $0.isWarning }
                            
                            if !actualPenalties.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("PENALITÀ")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.yellow)
                                    
                                    ForEach(actualPenalties) { penalty in
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.yellow)
                                                .font(.system(size: 11))
                                            Text(penalty.displayLabel)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                            if let note = penalty.note, !note.isEmpty {
                                                Text("- \(note)")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.kartDim)
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 4)
                            }
                            
                            if !warnings.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("AVVISI")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.kartDim)
                                    
                                    ForEach(warnings) { warning in
                                        HStack(spacing: 6) {
                                            Image(systemName: "exclamationmark.bubble.fill")
                                                .foregroundColor(.kartDim)
                                                .font(.system(size: 11))
                                            Text(warning.displayLabel)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                            if let note = warning.note, !note.isEmpty {
                                                Text("- \(note)")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.kartDim)
                                            }
                                        }
                                    }
                                }
                                .padding(.top, actualPenalties.isEmpty ? 4 : 8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if isExpanded {
                    expandedDriverId = nil
                } else {
                    expandedDriverId = driverId
                }
            }
        }
    }

    // ── Empty state ───────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if manager.isConnected {
                ProgressView().tint(Color.kartAccent).scaleEffect(1.3)
                Text("Attendo dati dal kartodromo...")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.kartDim)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 40))
                    .foregroundColor(.kartDim)
                Text("Connessione persa")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private func shortTime(_ iso: String) -> String {
        let parts = iso.split(separator: "T")
        guard parts.count == 2 else { return iso }
        return String(parts[1].prefix(8))
    }

    // MARK: - CSV Export con correzione penalità

    /// Costruisce il CSV della classifica istantanea applicando le penalità in tempo.
    /// Algoritmo:
    ///   1. Per ogni pilota, converte il gap (stringa) in secondi.
    ///   2. Calcola il gap rettificato = gapRaw + penalitàPilota − penalitàLeader.
    ///   3. Riordina per gap rettificato crescente (i distaccati su giro rimangono in fondo).
    ///   4. Ricalcola i gap relativi dal nuovo primo.
    ///   5. Serializza in CSV con colonne: Posizione, Squadra, Miglior Giro, Gap, Giri.
    private func buildCSV() -> URL? {
        guard let timing = manager.timing, !timing.rows.isEmpty else { return nil }

        let h = timing.headers
        let posIdx   = colIndex(in: h, keywords: ["pos", "pos.", "p", "#"]) ?? 0
        let kartIdx  = colIndex(in: h, keywords: ["kart", "num", "n°", "no", "bib"])
        let nameIdx  = colIndex(in: h, keywords: ["driver", "pilota", "name", "nome", "pilot"])
        let bestIdx  = colIndex(in: h, keywords: ["best", "migliore", "fastest", "record"])
        let gapIdx   = colIndex(in: h, keywords: ["gap", "diff", "distanza", "behind"])
        // "Giri" = contatore giri totali — non confondere con "Miglior Giro" (best lap time)
        let lapsIdx: Int? = h.indices.first { i in
            let col = h[i].lowercased().trimmingCharacters(in: .whitespaces)
            return col == "giri" || col == "laps" || col.contains("tours") || col.contains("rounds")
        }

        struct Entry {
            var originalPos: Int
            var name: String
            var bestLap: String
            var rawGapStr: String
            var rawGapSeconds: Double?  // nil = distacco in giri (es. "+1 giro")
            var lapsStr: String
            var kartNumber: Int?
            var penaltySeconds: Int
            var adjustedGap: Double?    // rawGapSeconds + penalitàPropria − penalitàLeader
            var hasBlackFlag: Bool
        }

        var entries: [Entry] = timing.rows.enumerated().map { idx, row in
            let posStr  = row.indices.contains(posIdx)  ? row[posIdx]  : "\(idx + 1)"
            let name    = nameIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? ""
            let best    = bestIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? "-"
            let gap     = gapIdx.flatMap  { row.indices.contains($0)  ? row[$0]  : nil } ?? ""
            let laps    = lapsIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? "-"
            let kartStr = kartIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? ""
            let kartNum = Int(kartStr.trimmingCharacters(in: .whitespaces))
            let kartPenalties = kartNum.map { viewModel.penaltiesByKart[$0] ?? [] } ?? []
            let penalty = kartNum.map { viewModel.totalPenaltySeconds(for: $0) } ?? 0
            let hasBlackFlag = kartPenalties.contains(where: { $0.penaltyType == "black_flag" })
            let gapSec  = parseGapToSeconds(gap)
            return Entry(
                originalPos: Int(posStr) ?? (idx + 1),
                name: name,
                bestLap: best,
                rawGapStr: gap,
                rawGapSeconds: gapSec,
                lapsStr: laps,
                kartNumber: kartNum,
                penaltySeconds: penalty,
                adjustedGap: nil,
                hasBlackFlag: hasBlackFlag
            )
        }

        // Penalità del leader attuale = il pilota con rawGapSeconds più basso (== 0)
        let leaderPenalty: Int = {
            let sameLap = entries.filter { $0.rawGapSeconds != nil }
            return sameLap.min(by: { $0.rawGapSeconds! < $1.rawGapSeconds! })?.penaltySeconds ?? 0
        }()

        // Gap rettificato per ogni pilota
        for i in entries.indices {
            if let raw = entries[i].rawGapSeconds {
                entries[i].adjustedGap = raw
                    + Double(entries[i].penaltySeconds)
                    - Double(leaderPenalty)
            }
            // adjustedGap rimane nil per i distaccati su giro
        }

        // Ordinamento: stesso giro → per adjustedGap crescente; distaccati su giro → posizione originale; squalificati in fondo
        let sameLap   = entries.filter { $0.adjustedGap != nil && !$0.hasBlackFlag }.sorted { $0.adjustedGap! < $1.adjustedGap! }
        let lapBehind = entries.filter { $0.adjustedGap == nil && !$0.hasBlackFlag }.sorted { $0.originalPos < $1.originalPos }
        let disqualified = entries.filter { $0.hasBlackFlag }.sorted { $0.originalPos < $1.originalPos }
        let sorted    = sameLap + lapBehind + disqualified

        let newLeaderAdj = sameLap.first?.adjustedGap ?? 0.0

        // Costruzione CSV
        var lines = ["Posizione,Kart,Squadra,Miglior Giro,Gap,Giri"]
        for (i, entry) in sorted.enumerated() {
            let gapStr: String
            if entry.hasBlackFlag {
                gapStr = "Squalificati"
            } else if i == 0 {
                gapStr = "Leader"
            } else if let adj = entry.adjustedGap {
                let diff = adj - newLeaderAdj
                gapStr = diff <= 0 ? "Leader" : formatGapSeconds(diff)
            } else {
                // Distaccato su giro: preserva la stringa originale (es. "+1 giro")
                gapStr = entry.rawGapStr
            }
            let safeName = entry.name.isEmpty    ? "-" : entry.name
            let safeBest = entry.bestLap.isEmpty || entry.bestLap == "-" ? "-" : entry.bestLap
            let safeKart = entry.kartNumber.map { String($0) } ?? "-"
            lines.append("\(i + 1),\(safeKart),\(safeName),\(safeBest),\(gapStr),\(entry.lapsStr)")
        }

        let csvString = lines.joined(separator: "\r\n")

        // Salvataggio in file temporaneo
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "classifica_\(df.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csvString.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Converte una stringa di gap (es. "+1:23.456", "+45.2", "Leader") in secondi.
    /// Restituisce nil se il gap è espresso in giri (es. "+1 giro") e non convertibile.
    private func parseGapToSeconds(_ gap: String) -> Double? {
        let s = gap.trimmingCharacters(in: .whitespaces).lowercased()
        // Leader / assente
        if s == "leader" || s.isEmpty || s == "-" || s == "0" { return 0.0 }
        // Distacchi in giri → non convertibili in secondi
        if s.contains("giro") || s.contains("giri") || s.contains("lap") || s.contains("tour") {
            return nil
        }
        let stripped = s.hasPrefix("+") ? String(s.dropFirst()) : s
        // Formato "M:SS.mmm"
        if stripped.contains(":") {
            let parts = stripped.split(separator: ":")
            if parts.count == 2,
               let mins = Double(parts[0]),
               let secs = Double(parts[1]) {
                return mins * 60 + secs
            }
        }
        // Formato "SS.mmm"
        return Double(stripped)
    }

    /// Formatta un gap in secondi come stringa CSV (es. "+45.230" oppure "+1:05.230").
    private func formatGapSeconds(_ seconds: Double) -> String {
        guard seconds > 0 else { return "Leader" }
        if seconds < 60 {
            return String(format: "+%.3f", seconds)
        }
        let mins = Int(seconds) / 60
        let secs = seconds - Double(mins * 60)
        return String(format: "+%d:%06.3f", mins, secs)
    }
}

// MARK: - Custom Shapes

/// Forma a "U" rovesciata per la griglia di partenza
private struct InvertedUShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

// MARK: - Share Sheet

/// Wrapper UIKit per UIActivityViewController (share/download del file CSV).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
