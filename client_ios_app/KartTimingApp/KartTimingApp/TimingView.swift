import SwiftUI

struct TimingView: View {
    let server: DiscoveredServer
    @StateObject private var manager = KartTimingManager()
    @State private var showURLSheet = false
    @State private var newURL = ""
    @State private var expandedDriverId: String? = nil

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Classifica
                if let timing = manager.timing, !timing.rows.isEmpty {
                    timingTable(timing: timing)
                } else {
                    emptyState
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newURL = manager.currentURL
                    showURLSheet = true
                } label: {
                    Image(systemName: "link.badge.plus").foregroundColor(.kartAccent)
                }
            }
        }
        .sheet(isPresented: $showURLSheet) {
            urlSheet
        }
        .onAppear { manager.connect(to: server) }
        .onDisappear { manager.disconnect() }
    }

    // ── Status bar ────────────────────────────────────────────────────────

    private var statusBar: some View {
        HStack(spacing: 10) {
            // Connessione
            HStack(spacing: 5) {
                Circle()
                    .fill(manager.isConnected ? Color.kartGreen : Color.kartRed)
                    .frame(width: 7, height: 7)
                Text(manager.isConnected ? "Connesso" : "Disconnesso")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kartPanel)
    }

    // ── Tabella classifica ────────────────────────────────────────────────

    /// Indice della colonna il cui header contiene una delle keyword (case-insensitive)
    private func colIndex(in headers: [String], keywords: [String]) -> Int? {
        for kw in keywords {
            if let i = headers.firstIndex(where: { $0.lowercased().contains(kw) }) {
                return i
            }
        }
        return nil
    }

    /// Abbreviazione nome: prime 3 lettere maiuscole (solo alfa)
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

        // Colonne "secondarie" = tutto ciò che non è già nelle 6 chiave
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

        // Colonne secondarie non vuote
        let extras: [(String, String)] = headers.indices.compactMap { i in
            guard !primarySet.contains(i),
                  row.indices.contains(i),
                  !row[i].trimmingCharacters(in: .whitespaces).isEmpty
            else { return nil }
            return (headers[i], row[i])
        }

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
                        }

                        // Extra secondari (es. squadra, classe…)
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
                        // Ultimo giro (primario)
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
                    
                    // Chevron di stato espansione
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
                        // Nome completo in evidenza
                        if !fullName.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PILOTA (NOME COMPLETO)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.kartDim)
                                Text(fullName)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Griglia dinamica con tutti i dettagli/colonne ricevute
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
                                        Text(item.value.isEmpty ? "-" : item.value)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
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
                Text("Attendo dati dal kartdromo…")
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

    // ── URL Sheet ─────────────────────────────────────────────────────────

    private var urlSheet: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("URL kartdromo")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.kartDim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("https://live.racefacer.com/...", text: $newURL)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(12)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(10)

                    Button {
                        if newURL.hasPrefix("http") {
                            manager.sendCommand("set_url", extra: ["url": newURL])
                            showURLSheet = false
                        }
                    } label: {
                        Text("Aggiorna URL")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.kartAccent)
                            .cornerRadius(12)
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Cambia sorgente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annulla") { showURLSheet = false }
                        .foregroundColor(.kartAccent)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private func shortTime(_ iso: String) -> String {
        let parts = iso.split(separator: "T")
        guard parts.count == 2 else { return iso }
        return String(parts[1].prefix(8))
    }
}
