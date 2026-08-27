import SwiftUI
import UIKit

/// Vista Classifica Live per il Race Director.
/// Mostra la classifica proveniente dal WebSocket,
/// con badge per le penalità totali di ogni kart.
struct ClassificaLiveView: View {
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var manager: KartTimingManager

    /// Binding settato a `true` dal parent (DirectorLiveView) per triggerare l'export.
    @Binding var exportRequested: Bool

    @State private var expandedDriverId: String? = nil

    // CSV export
    @State private var showShareSheet = false
    @State private var csvExportURL: URL? = nil
    
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
                // Status bar
                statusBar

                if let timing = manager.timing, !timing.rows.isEmpty {
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

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(isLeader
                      ? Color.kartAccent.opacity(0.12)
                      : Color.kartPanel)

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
                            if actualPenaltiesCount > 0 {
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
        }

        var entries: [Entry] = timing.rows.enumerated().map { idx, row in
            let posStr  = row.indices.contains(posIdx)  ? row[posIdx]  : "\(idx + 1)"
            let name    = nameIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? ""
            let best    = bestIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? "-"
            let gap     = gapIdx.flatMap  { row.indices.contains($0)  ? row[$0]  : nil } ?? ""
            let laps    = lapsIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? "-"
            let kartStr = kartIdx.flatMap { row.indices.contains($0)  ? row[$0]  : nil } ?? ""
            let kartNum = Int(kartStr.trimmingCharacters(in: .whitespaces))
            let penalty = kartNum.map { viewModel.totalPenaltySeconds(for: $0) } ?? 0
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
                adjustedGap: nil
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

        // Ordinamento: stesso giro → per adjustedGap crescente; distaccati su giro → posizione originale
        let sameLap   = entries.filter { $0.adjustedGap != nil }.sorted { $0.adjustedGap! < $1.adjustedGap! }
        let lapBehind = entries.filter { $0.adjustedGap == nil  }.sorted { $0.originalPos < $1.originalPos }
        let sorted    = sameLap + lapBehind

        let newLeaderAdj = sameLap.first?.adjustedGap ?? 0.0

        // Costruzione CSV
        var lines = ["Posizione,Kart,Squadra,Miglior Giro,Gap,Giri"]
        for (i, entry) in sorted.enumerated() {
            let gapStr: String
            if i == 0 {
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

// MARK: - Share Sheet

/// Wrapper UIKit per UIActivityViewController (share/download del file CSV).
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
