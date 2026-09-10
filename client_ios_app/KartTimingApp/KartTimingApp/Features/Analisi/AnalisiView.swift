import SwiftUI
import Charts

// MARK: - AnalisiView

struct AnalisiView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = AnalisiViewModel()

    @State private var selectedSegment: Int = 0
    @State private var showAddCircuitTimeSheet = false
    @State private var selectedCircuitName: String? = nil

    // MARK: – Role check
    private var isAdminOrDirector: Bool {
        let role = authState.currentUser?.role
        return role == .admin || role == .raceDirector
    }

    var body: some View {
        if isAdminOrDirector {
            // Gli admin vedono direttamente la schermata di ricerca utenti
            AdminAnalisiView(server: server)
                .environmentObject(authState)
        } else {
            // Gli utenti normali vedono la propria analisi
            userAnalisiContent
        }
    }

    @ViewBuilder
    private var userAnalisiContent: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView().tint(.kartAccent).scaleEffect(1.5)
                    Text("Caricamento analisi...")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.kartDim)
                }
            } else {
                VStack(spacing: 0) {
                    segmentBar
                    pageContent
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.fetchAll(serverURL: server.httpURL, token: authState.currentToken)
        }
    }

    // MARK: – Segment bar

    private var segmentBar: some View {
        let labels = ["Panoramica", "Storico", "Circuiti"]
        return HStack(spacing: 0) {
            ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedSegment = i
                    }
                } label: {
                    VStack(spacing: 5) {
                        Text(label)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(selectedSegment == i ? .kartAccent : .kartDim)
                            .padding(.top, 10)
                        Rectangle()
                            .fill(selectedSegment == i ? Color.kartAccent : Color.clear)
                            .frame(height: 2)
                            .cornerRadius(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(Color.kartPanel)
    }

    // MARK: – Page content

    @ViewBuilder
    private var pageContent: some View {
        TabView(selection: $selectedSegment) {
            panoramicaContent.tag(0)
            storicoContent.tag(1)
            circuitiContent.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut(duration: 0.25), value: selectedSegment)
    }

    // MARK: ─── Panoramica ─────────────────────────────────────────────────────

    private var panoramicaContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                Spacer(minLength: 30)
            }
            .padding(16)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text("RIEPILOGO STAGIONE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
            }
            .padding(14)
            .background(Color.kartAccent.opacity(0.08))

            // Stats 2x2
            let stats: [(String, String, String)] = [
                ("flag.fill",        "\(viewModel.totalPastRaces)",         "Gare disputate"),
                ("mappin.and.ellipse", "\(viewModel.totalCircuitsVisited)", "Circuiti visitati"),
                ("trophy.fill",      viewModel.bestOfficialPosition.map { "\($0)°" } ?? "—", "Miglior posizione"),
                ("calendar.badge.checkmark", "\(viewModel.upcomingConfirmedEvents.count)", "Prossime gare"),
            ]

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1) {
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    statCell(icon: stat.0, value: stat.1, label: stat.2)
                }
            }
            .background(Color.kartForeground.opacity(0.04))
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.kartBorder(opacity: 0.06), lineWidth: 1))
    }

    private func statCell(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.kartAccent)
            Text(value)
                .font(.system(size: 26, weight: .black, design: .monospaced))
                .foregroundColor(.kartForeground)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.kartDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.kartPanel)
    }


    // MARK: ─── Storico ────────────────────────────────────────────────────────

    private var storicoContent: some View {
        Group {
            if viewModel.pastConfirmedEvents.isEmpty {
                emptyState(icon: "flag.slash", message: "Nessuna gara disputata ancora",
                           sub: "Le gare confermate passate appariranno qui")
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.pastConfirmedEvents, id: \.event.id) { item in
                            PastEventCard(
                                event: item.event,
                                result: viewModel.result(for: item.event.id),
                                server: server,
                                viewModel: viewModel
                            )
                            .environmentObject(authState)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // MARK: ─── Circuiti ───────────────────────────────────────────────────────

    /// Circuiti filtrati in base alla selezione corrente
    private var filteredCircuitStats: [CircuitStat] {
        guard let name = selectedCircuitName else { return viewModel.circuitStats }
        return viewModel.circuitStats.filter { $0.circuitName == name }
    }

    private var circuitiContent: some View {
        VStack(spacing: 0) {
            if !viewModel.isReadOnly {
                Button {
                    showAddCircuitTimeSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Aggiungi tempo dichiarato")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .cornerRadius(12)
                }
                .padding(16)
            }

            // ── Selettore circuito nativo iOS ──────────────────────────────
            if !viewModel.allKartodromi.isEmpty {
                circuitPickerBar
            }

            Group {
                if viewModel.allKartodromi.isEmpty {
                    emptyState(icon: "map.slash", message: "Nessun circuito disponibile",
                               sub: "Nessun kartodromo registrato nel sistema")
                } else if filteredCircuitStats.isEmpty {
                    emptyState(icon: "flag.slash",
                               message: selectedCircuitName != nil ? "Nessun dato per questo circuito" : "Nessun dato",
                               sub: selectedCircuitName != nil ? "Aggiungi il tuo primo tempo con il pulsante in alto" : "I dati appariranno dopo le prime gare")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(filteredCircuitStats) { stat in
                                CircuitCard(stat: stat)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCircuitTimeSheet) {
            AddCircuitTimeSheet(viewModel: viewModel, server: server)
                .environmentObject(authState)
        }
    }

    /// Selettore circuito nativo con Picker stile .menu
    private var circuitPickerBar: some View {
        HStack {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.kartAccent)

            Picker("Circuito", selection: $selectedCircuitName) {
                Text("Tutti i circuiti").tag(String?.none)
                ForEach(viewModel.allKartodromi) { k in
                    Text(k.nome).tag(Optional(k.nome))
                }
            }
            .pickerStyle(.menu)
            .accentColor(.kartAccent)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            if selectedCircuitName != nil {
                Button {
                    withAnimation { selectedCircuitName = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.kartDim)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kartPanel.opacity(0.6))
    }

    // MARK: – Shared helpers

    private func sectionHeader(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.kartAccent)
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.kartAccent)
        }
    }

    private func emptyState(icon: String, message: String, sub: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundColor(.kartDim)
            Text(message)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.kartDim)
            Text(sub)
                .font(.system(size: 12))
                .foregroundColor(.kartDim)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(32)
    }
}

// MARK: - PastEventCard

struct PastEventCard: View {
    let event: RaceEvent
    let result: EventResult?
    let server: DiscoveredServer
    @ObservedObject var viewModel: AnalisiViewModel
    @EnvironmentObject var authState: AuthState

    @State private var showClassification = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────────────────────────
            HStack(spacing: 10) {
                positionBadge(result?.position)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.kartForeground)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Label(event.location.components(separatedBy: " - ").first ?? event.location,
                              systemImage: "mappin.circle")
                        if let date = viewModel.parseDate(from: event.eventDate) {
                            Text(date, style: .date)
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.kartDim)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider().background(Color.kartBorder(opacity: 0.07))

            // ── Tempi ───────────────────────────────────────────────────────
            HStack(spacing: 0) {
                if let res = result {
                    lapChip(label: "⏱ MIGLIOR GIRO", time: res.formattedBestLap, gap: res.gap, laps: res.laps, accent: .kartAccent)
                }

                Spacer()

                Button {
                    viewModel.fetchClassification(serverURL: server.httpURL,
                                                   eventId: event.id,
                                                   token: authState.currentToken)
                    showClassification = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "list.number")
                        Text("Classifica")
                    }
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.kartForeground)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.kartAccent.opacity(0.15))
                    .cornerRadius(6)
                }
                .padding(.trailing, 14)
                .padding(.vertical, 10)
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.05), lineWidth: 1))
        .sheet(isPresented: $showClassification) {
            ClassificationSheet(event: event, viewModel: viewModel, server: server)
                .environmentObject(authState)
        }
    }

    private func positionBadge(_ position: Int?) -> some View {
        let (color, text): (Color, String) = {
            switch position {
            case 1:  return (.yellow, "1°")
            case 2:  return (Color(white: 0.75), "2°")
            case 3:  return (Color(red: 0.8, green: 0.5, blue: 0.2), "3°")
            default:
                if let p = position { return (.kartDim, "\(p)°") }
                return (.kartDim, "?")
            }
        }()

        return ZStack {
            Circle().fill(color.opacity(0.18)).frame(width: 42, height: 42)
            Text(text)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func lapChip(label: String, time: String?, gap: String?, laps: Int?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(accent.opacity(0.7))
            Text(time ?? "—")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
            
            if let gap = gap {
                Text("Gap: \(gap)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
            if let laps = laps {
                Text("\(laps) Giri")
                    .font(.system(size: 9))
                    .foregroundColor(.kartDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - CircuitCard

struct CircuitCard: View {
    let stat: CircuitStat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ───────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text(stat.circuitName.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartForeground)
                Spacer()
                Text("\(stat.racesCount) \(stat.racesCount == 1 ? "gara" : "gare")")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
            .padding(14)
            .background(Color.kartAccent.opacity(0.06))

            // ── Stats mini ────────────────────────────────────────────────
            HStack(spacing: 20) {
                miniStat(label: "MIGLIOR GARA",
                         value: stat.bestEventLapMs.flatMap { ms -> String? in
                             EventResult(id: 0, eventId: 0, userId: nil, driverName: nil, memberEmail: nil,
                                         position: nil, bestLapMs: ms, gap: nil, laps: nil, isOfficial: true,
                                         teamId: nil, teamName: nil, note: nil, username: nil, kartNumber: nil,
                                         resultType: nil, profilePictureUrl: nil, createdAt: "")
                             .formattedBestLap
                         } ?? "—",
                         accent: .kartAccent)

                miniStat(label: "PROVA LIBERA",
                         value: stat.bestSelfLapMs.flatMap { ms -> String? in
                             EventResult(id: 0, eventId: 0, userId: nil, driverName: nil, memberEmail: nil,
                                         position: nil, bestLapMs: ms, gap: nil, laps: nil, isOfficial: false,
                                         teamId: nil, teamName: nil, note: nil, username: nil, kartNumber: nil,
                                         resultType: nil, profilePictureUrl: nil, createdAt: "")
                             .formattedBestLap
                         } ?? "—",
                         accent: .orange)

                miniStat(label: "MIGLIOR POS.",
                         value: stat.bestPosition.map { "\($0)°" } ?? "—",
                         accent: .kartDim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            // ── Swift Chart ───────────────────────────────────────────────
            if stat.hasAnyLapData {
                Divider().background(Color.kartBorder(opacity: 0.07))
                lapChart
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.kartBorder(opacity: 0.05), lineWidth: 1))
    }

    private func miniStat(label: String, value: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.kartDim)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
        }
    }

    @ViewBuilder
    private var lapChart: some View {
        let points = stat.chartPoints
        if #available(iOS 16.0, *) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    chartLegendDot(color: .kartAccent, label: "Gara")
                    chartLegendDot(color: .orange,     label: "Prova Libera")
                }
                .font(.system(size: 9, weight: .semibold))
                
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("Data",    point.date),
                            y: .value("Tempo",   point.lapSeconds)
                        )
                        .foregroundStyle(point.isOfficial ? Color.kartAccent : Color.orange)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Data",    point.date),
                            y: .value("Tempo",   point.lapSeconds)
                        )
                        .foregroundStyle(point.isOfficial ? Color.kartAccent : Color.orange)
                        .symbolSize(40)
                        .annotation(position: .top) {
                            Text(formatSecs(point.lapSeconds))
                                .font(.system(size: 7, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                    }

                    // Area sotto la linea
                    ForEach(points) { point in
                        AreaMark(
                            x: .value("Data",  point.date),
                            y: .value("Tempo", point.lapSeconds)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.kartAccent.opacity(0.25), Color.clear],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { val in
                        AxisGridLine().foregroundStyle(Color.kartBorder(opacity: 0.06))
                        AxisValueLabel {
                            if let s = val.as(Double.self) {
                                Text(formatSecs(s))
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.kartDim)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: min(points.count, 4))) { _ in
                        AxisGridLine().foregroundStyle(Color.kartBorder(opacity: 0.06))
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 8))
                            .foregroundStyle(Color.kartDim)
                    }
                }
                .frame(height: 160)
            }
        } else {
            Text("Grafico disponibile su iOS 16+")
                .font(.caption)
                .foregroundColor(.kartDim)
        }
    }

    private func chartLegendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).foregroundColor(.kartDim)
        }
    }


    private func formatSecs(_ s: Double) -> String {
        let ms = Int(s * 1000)
        let minutes = ms / 60_000
        let seconds = (ms % 60_000) / 1_000
        let millis  = ms % 1_000
        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, millis)
        }
        return String(format: "%d.%03d", seconds, millis)
    }
}

// MARK: - ClassificationSheet

struct ClassificationSheet: View {
    let event: RaceEvent
    @ObservedObject var viewModel: AnalisiViewModel
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                let results = viewModel.classifications[event.id] ?? []

                if results.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "trophy.slash")
                            .font(.system(size: 44))
                            .foregroundColor(.kartDim)
                        Text("Classifica non ancora pubblicata")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.kartDim)
                        Text("L'admin pubblicherà i risultati dopo la gara")
                            .font(.system(size: 12))
                            .foregroundColor(.kartDim)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    let isTeamRace = results.contains { r in
                        !(r.teamName ?? "").isEmpty
                    }

                    ScrollView {
                        VStack(spacing: 10) {
                            if isTeamRace {
                                teamClassification(results)
                            } else {
                                individualClassification(results)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Classifica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }.foregroundColor(.kartAccent)
                }
            }
        }
    }

    // ── Helper: utente corrente ───────────────────────────────────────────────

    private var currentUserId: Int? {
        viewModel.targetUserId ?? authState.currentUser?.id
    }

    // ── Classifica Individuale ────────────────────────────────────────────────

    @ViewBuilder
    private func individualClassification(_ results: [EventResult]) -> some View {
        ForEach(results.sorted { ($0.position ?? 999) < ($1.position ?? 999) }) { result in
            individualRow(result)
        }
    }

    private func individualRow(_ result: EventResult) -> some View {
        let (bgColor, strokeColor) = podiumColors(result.position)
        let isMe = result.userId != nil && result.userId == currentUserId
        let borderColor = isMe ? Color.kartForeground.opacity(0.85) : strokeColor
        let borderWidth: CGFloat = isMe ? 2.0 : 1

        return HStack(spacing: 12) {
            positionBadge(result.position)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let k = result.kartNumber {
                        Text("#\(k)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartForeground)
                    }
                    Text(result.displayName)
                        .font(.system(size: 14, weight: isMe ? .bold : .semibold))
                        .foregroundColor(.kartForeground)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let lap = result.formattedBestLap {
                        HStack(spacing: 4) {
                            Image(systemName: "stopwatch").font(.system(size: 10))
                            Text(lap)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    }
                    if let gap = result.gap {
                        Text(gap)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                }
            }
            Spacer()
            if let laps = result.laps {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(laps)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartForeground)
                    Text(laps == 1 ? "Giro" : "Giri")
                        .font(.system(size: 10))
                        .foregroundColor(.kartDim)
                }
            }
        }
        .padding(12)
        .background(isMe ? bgColor.opacity(1.0) : bgColor)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: borderWidth))
        .scaleEffect(isMe ? 1.05 : 1.0)
        .zIndex(isMe ? 1 : 0)
    }

    // ── Classifica a Squadre ──────────────────────────────────────────────────

    @ViewBuilder
    private func teamClassification(_ results: [EventResult]) -> some View {
        let teams = buildUniqueTeams(results)
        ForEach(teams, id: \.teamName) { team in
            teamRow(team)
        }
    }

    private struct TeamRow {
        let teamName: String
        let position: Int?
        let gap: String?
        let bestLapMs: Int?
        let laps: Int?
        let isMyTeam: Bool
        let kartNumber: Int?
    }

    private func buildUniqueTeams(_ results: [EventResult]) -> [TeamRow] {
        // Raggruppa per team_name, un solo rappresentante per squadra
        var seen: Set<String> = []
        var teams: [TeamRow] = []
        let sorted = results.sorted { ($0.position ?? 999) < ($1.position ?? 999) }
        for r in sorted {
            let key = r.teamName ?? r.displayName
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            // Controlla se l'utente corrente è in questo team
            let isMyTeam: Bool = {
                guard let uid = currentUserId else { return false }
                return results
                    .filter { ($0.teamName ?? $0.displayName) == key }
                    .contains { $0.userId == uid }
            }()
            teams.append(TeamRow(
                teamName: key,
                position: r.position,
                gap: r.gap,
                bestLapMs: r.bestLapMs,
                laps: r.laps,
                isMyTeam: isMyTeam,
                kartNumber: r.kartNumber
            ))
        }
        return teams
    }

    private func teamRow(_ team: TeamRow) -> some View {
        let (bgColor, strokeColor) = podiumColors(team.position)
        let borderColor = team.isMyTeam ? Color.kartForeground.opacity(0.85) : strokeColor
        let borderWidth: CGFloat = team.isMyTeam ? 2.0 : 1

        return HStack(spacing: 12) {
            positionBadge(team.position)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let k = team.kartNumber {
                        Text("#\(k)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartForeground)
                    }
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.kartDim)
                    Text(team.teamName)
                        .font(.system(size: 14, weight: team.isMyTeam ? .bold : .semibold))
                        .foregroundColor(.kartForeground)
                        .lineLimit(1)
                }

                HStack(spacing: 12) {
                    if let ms = team.bestLapMs {
                        let mins = ms / 60_000
                        let secs = (ms % 60_000) / 1_000
                        let mill = ms % 1_000
                        let lapStr = mins > 0
                            ? String(format: "%d:%02d.%03d", mins, secs, mill)
                            : String(format: "%d.%03d", secs, mill)
                        HStack(spacing: 4) {
                            Image(systemName: "stopwatch").font(.system(size: 10))
                            Text(lapStr)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    }
                    if let gap = team.gap {
                        Text(gap)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(gap == "Leader" ? .kartAccent : .kartDim)
                    }
                }
            }
            Spacer()
            if let laps = team.laps {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(laps)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartForeground)
                    Text(laps == 1 ? "Giro" : "Giri")
                        .font(.system(size: 10))
                        .foregroundColor(.kartDim)
                }
            }
        }
        .padding(12)
        .background(bgColor)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(borderColor, lineWidth: borderWidth))
        .scaleEffect(team.isMyTeam ? 1.05 : 1.0)
        .zIndex(team.isMyTeam ? 1 : 0)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private func podiumColors(_ position: Int?) -> (Color, Color) {
        switch position {
        case 1: return (Color.yellow.opacity(0.07), Color.yellow.opacity(0.3))
        case 2: return (Color(white: 0.5).opacity(0.07), Color(white: 0.6).opacity(0.25))
        case 3: return (Color.orange.opacity(0.07), Color.orange.opacity(0.25))
        default: return (Color.kartPanel, Color.kartForeground.opacity(0.06))
        }
    }

    private func positionBadge(_ position: Int?) -> some View {
        let (bg, fg): (Color, Color) = {
            switch position {
            case 1: return (.yellow.opacity(0.2), .yellow)
            case 2: return (Color(white: 0.5).opacity(0.2), Color(white: 0.85))
            case 3: return (.orange.opacity(0.2), .orange)
            default: return (.kartPanel, .kartDim)
            }
        }()
        return ZStack {
            Circle().fill(bg).frame(width: 36, height: 36)
            Text(position.map { "\($0)°" } ?? "—")
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .foregroundColor(fg)
        }
    }
}


// MARK: - AddCircuitTimeSheet

struct AddCircuitTimeSheet: View {
    @ObservedObject var viewModel: AnalisiViewModel
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKartodromoId: Int?
    @State private var minInput: String = ""
    @State private var secInput: String = ""
    @State private var msInput:  String = ""
    @State private var selectedDate: Date = Date()
    @State private var isSaving = false
    @State private var errorText: String? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        
                        // Circuito Picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Circuito *")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.kartDim)
                            
                            Menu {
                                ForEach(viewModel.allKartodromi) { k in
                                    Button(k.nome) {
                                        selectedKartodromoId = k.id
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(selectedKartodromoName ?? "Seleziona un circuito")
                                        .foregroundColor(selectedKartodromoId == nil ? .kartDim : .kartForeground)
                                        .font(.system(size: 16, weight: .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundColor(.kartDim)
                                }
                                .padding(14)
                                .background(Color.kartPanel)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.kartBorder(opacity: 0.06), lineWidth: 1))
                            }
                        }
                        .padding(.top, 8)

                        // Data picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Data *")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.kartDim)
                            
                            DatePicker(
                                "",
                                selection: $selectedDate,
                                displayedComponents: [.date]
                            )
                            .datePickerStyle(.compact)
                            .labelsHidden()
                        }

                        // Best lap structured input
                        structuredTimeInput

                        if let err = errorText {
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                Text(err)
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.kartRed)
                            .padding(10)
                            .background(Color.kartRed.opacity(0.1))
                            .cornerRadius(8)
                        }

                        // Info badge
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                            Text("Il tempo sarà associato al circuito e visibile solo a te (prove libere/record personale).")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.kartDim)
                        .padding(12)
                        .background(Color.kartPanel)
                        .cornerRadius(10)

                        // Save button
                        Button(action: save) {
                            if isSaving {
                                ProgressView().tint(canSave ? .white : .kartDim)
                            } else {
                                Text("Salva tempo")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(!canSave ? Color.kartDim.opacity(0.3) : Color.kartAccent)
                        .foregroundColor(!canSave ? .kartDim : .white)
                        .cornerRadius(12)
                        .disabled(!canSave || isSaving)

                        Spacer(minLength: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Aggiungi Tempo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }.foregroundColor(.kartAccent)
                }
            }
        }
    }
    
    private var selectedKartodromoName: String? {
        guard let id = selectedKartodromoId else { return nil }
        return viewModel.allKartodromi.first(where: { $0.id == id })?.nome
    }
    
    private var canSave: Bool {
        selectedKartodromoId != nil && !(minInput.isEmpty && secInput.isEmpty && msInput.isEmpty)
    }
    
    private var structuredTimeInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Miglior giro *")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.kartDim)
                
            HStack(spacing: 8) {
                timeField("Min", text: $minInput)
                Text(":").font(.system(size: 24, weight: .bold)).foregroundColor(.kartDim)
                timeField("Sec", text: $secInput)
                Text(".").font(.system(size: 24, weight: .bold)).foregroundColor(.kartDim)
                timeField("Ms", text: $msInput)
            }
        }
    }
    
    private func timeField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .foregroundColor(.kartForeground)
            .multilineTextAlignment(.center)
            .keyboardType(.numberPad)
            .padding(14)
            .background(Color.kartPanel)
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(text.wrappedValue.isEmpty ? Color.kartBorder(opacity: 0.06) : Color.kartAccent.opacity(0.4),
                        lineWidth: 1))
    }

    private func save() {
        guard let kid = selectedKartodromoId else { return }
        
        let m = Int(minInput.trimmingCharacters(in: .whitespaces)) ?? 0
        let s = Int(secInput.trimmingCharacters(in: .whitespaces)) ?? 0
        let ms = Int(msInput.trimmingCharacters(in: .whitespaces)) ?? 0
        
        let totalMs = (m * 60000) + (s * 1000) + ms
        
        if totalMs <= 0 {
            errorText = "Inserisci un tempo valido maggiore di zero."
            return
        }
        
        errorText = nil
        isSaving  = true

        viewModel.declareKartodromoResult(
            serverURL: server.httpURL,
            kartodromoId: kid,
            bestLapMs: totalMs,
            date: selectedDate,
            token: authState.currentToken
        ) { success in
            isSaving = false
            if success {
                dismiss()
            } else {
                errorText = "Errore durante il salvataggio."
            }
        }
    }

    private func parseTime(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let colonParts = t.components(separatedBy: ":")
        if colonParts.count == 2 {
            guard let min = Int(colonParts[0]) else { return nil }
            guard let rest = parseSecondsMs(colonParts[1]) else { return nil }
            return min * 60_000 + rest
        } else if colonParts.count == 1 {
            return parseSecondsMs(t)
        }
        return nil
    }

    private func parseSecondsMs(_ s: String) -> Int? {
        let parts = s.components(separatedBy: ".")
        guard let sec = Int(parts[0]) else { return nil }
        var ms = 0
        if parts.count > 1 {
            let msStr = String(parts[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            ms = Int(msStr) ?? 0
        }
        return sec * 1_000 + ms
    }
}
