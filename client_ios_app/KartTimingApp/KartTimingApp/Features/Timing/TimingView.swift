import SwiftUI

struct TimingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let server: DiscoveredServer
    var isTabActive: Bool = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = KartTimingManager()
    @State private var expandedDriverId: String? = nil
    @State private var selectedKartodromo: Kartodromo? = nil
    @State private var showTrackPicker = false
    @State private var trackSearch = ""
    @State private var kartodromi: [Kartodromo] = []
    @State private var isLoadingTracks = false
    @State private var trackLoadError: String? = nil
    @State private var navigateToPilot = false

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                statusBar

                if selectedKartodromo != nil {
                    // Classifica
                    if let timing = manager.timing, !timing.rows.isEmpty {
                        timingTable(timing: timing)
                    } else {
                        emptyState
                    }
                } else {
                    // Nessuna pista selezionata
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 44))
                            .foregroundColor(.kartDim)
                        Text("Selezionare tracciato")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.kartDim)
                    }
                    Spacer()
                }

                // Barra LOGIN / REGISTER (solo per sessione guest)
                if authState.isGuestSession {
                    guestLoginBar
                }
            }
        }
        .onAppear {
            isVisible = true
            updateConnection()
        }
        .onDisappear {
            isVisible = false
            if !navigateToPilot { manager.disconnect() }
        }
        .onChange(of: isTabActive) { _, _ in updateConnection() }
        .onChange(of: scenePhase) { _, _ in updateConnection() }
        .onChange(of: selectedKartodromo?.id) { _, _ in updateConnection() }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Nessun back button necessario perché ora gestiamo la navigazione tramite la barra inferiore in HomeView

            // Picker pista al centro della toolbar
            ToolbarItem(placement: .principal) {
                Button {
                    trackSearch = ""
                    showTrackPicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 12, weight: .bold))
                        Text(selectedKartodromo.map { shortTrackName($0.nome) } ?? "SELEZIONA PISTA")
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.82, blue: 0.0),
                                     Color(red: 1.0, green: 0.65, blue: 0.0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.4), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showTrackPicker) {
                    trackPickerSheet
                }
            }

            // Pulsante area pilota
            if selectedKartodromo != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        navigateToPilot = true
                    } label: {
                        Image(systemName: "car.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $navigateToPilot) {
            TimingPilotView()
                .environmentObject(manager)
        }
        .alert("Operazione negata", isPresented: $manager.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(manager.errorMessage ?? "Si è verificato un errore sul server.")
        }
    }


    private func updateConnection() {
        guard isTabActive, scenePhase == .active, isVisible || navigateToPilot,
              let track = selectedKartodromo else {
            manager.disconnect()
            return
        }
        if !manager.isConnected { manager.connect(to: server) }
        manager.sendCommand("set_url", extra: ["url": track.url])
    }

    // ── Track picker sheet ────────────────────────────────────────────────

    /// Rimuove la parte tra parentesi dal nome (es. "Ottobiano Motorsport (Ottobiano, PV)" → "Ottobiano Motorsport")
    private func shortTrackName(_ nome: String) -> String {
        if let parenRange = nome.range(of: "(") {
            return String(nome[nome.startIndex..<parenRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
        }
        return nome
    }

    private var filteredKartodromi: [Kartodromo] {
        let q = trackSearch.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return kartodromi }
        return kartodromi.filter {
            $0.nome.localizedCaseInsensitiveContains(q) ||
            $0.luogo.localizedCaseInsensitiveContains(q)
        }
    }

    private var trackPickerSheet: some View {
        NavigationStack {
            List {
                // Voce deseleziona
                Button {
                    selectedKartodromo = nil
                    manager.disconnect()
                    showTrackPicker = false
                } label: {
                    HStack {
                        Image(systemName: selectedKartodromo == nil ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selectedKartodromo == nil ? .kartAccent : .kartDim)
                        Text("-- SELEZIONA PISTA --")
                            .italic()
                            .foregroundColor(.primary)
                    }
                }

                // Kartodromi filtrati
                ForEach(filteredKartodromi) { k in
                    Button {
                        selectedKartodromo = k
                        showTrackPicker = false
                    } label: {
                        HStack {
                            Image(systemName: selectedKartodromo?.id == k.id ? "checkmark.circle.fill" : "flag.fill")
                                .foregroundColor(selectedKartodromo?.id == k.id ? .kartAccent : .kartDim)
                            Text(k.nome)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .searchable(text: $trackSearch, placement: .navigationBarDrawer(displayMode: .always), prompt: "Cerca kartadromo…")
            .navigationTitle("Seleziona pista")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { showTrackPicker = false }
                }
            }
            .overlay {
                if isLoadingTracks {
                    ProgressView("Caricamento piste…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert("Impossibile caricare le piste", isPresented: Binding(
                get: { trackLoadError != nil },
                set: { if !$0 { trackLoadError = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(trackLoadError ?? "")
            }
            .onAppear {
                guard let token = authState.currentToken else { return }
                let base = AppEnvironment.shared.baseURL
                Task {
                    isLoadingTracks = true
                    defer { isLoadingTracks = false }
                    do {
                        kartodromi = try await KartodromoService.fetchKartodromi(
                            baseURL: base,
                            accessToken: token
                        )
                    } catch {
                        trackLoadError = error.localizedDescription
                    }
                }
            }
        }
    }

    // ── Guest login bar ───────────────────────────────────────────────────

    private var guestLoginBar: some View {
        Button {
            authState.logout()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                Text("LOGIN / REGISTER")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(1)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.82, blue: 0.0),
                             Color(red: 1.0, green: 0.65, blue: 0.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
        .buttonStyle(.plain)
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
            LazyVStack(spacing: 6) {
                ForEach(timing.displayRows) { item in
                    let idx = item.index
                    let row = item.values
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

        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 1)) {
                expandedDriverId = isExpanded ? nil : driverId
            }
        } label: {
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
                        .fill(Color.kartForeground.opacity(0.06))
                        .frame(width: 1, height: 44)

                    // ── Kart # + Nome ──────────────────────────────────────
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if !kart.isEmpty {
                                Text("#\(kart)")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(.kartForeground)
                            }
                            if !shortName.isEmpty {
                                Text(shortName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundColor(isLeader ? .kartAccent : .kartForeground)
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
                            .foregroundColor(isLeader ? .kartAccent : .kartForeground)

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
                        .background(Color.kartForeground.opacity(0.1))
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
                                    .foregroundColor(.kartForeground)
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
                                if !["driver", "pilota", "name", "nome", "pilot", "pit"].contains(item.header.lowercased()) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.header.uppercased())
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(.kartDim)
                                        Text(item.value.isEmpty ? "-" : item.value)
                                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.kartForeground)
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
        }
        .buttonStyle(KartPressButtonStyle())
        .accessibilityValue(isExpanded ? "Dettagli aperti" : "Dettagli chiusi")

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

    // ── Helpers ───────────────────────────────────────────────────────────

    private func shortTime(_ iso: String) -> String {
        let parts = iso.split(separator: "T")
        guard parts.count == 2 else { return iso }
        return String(parts[1].prefix(8))
    }
}
