import SwiftUI

struct EventDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authState: AuthState
    let server: DiscoveredServer
    let event: RaceEvent
    @StateObject private var kartodromoVM = KartodromoViewModel()

    @State private var showLive = false
    @State private var isUpdatingStatus = false
    @State private var statusError: String? = nil
    @State private var localEvent: RaceEvent

    init(server: DiscoveredServer, event: RaceEvent) {
        self.server = server
        self.event = event
        _localEvent = State(initialValue: event)
    }

    // Ruolo utente — usato in tutti i sotto-componenti per decidere
    // se mostrare i campi non compilati (solo l'admin li vede).
    private var isAdmin: Bool {
        authState.currentUser?.role.canManageUsers == true
    }

    /// True se l'utente può gestire lo stato della gara (race_director o admin)
    private var isDirectorOrAdmin: Bool {
        let role = authState.currentUser?.role
        return role == .raceDirector || role == .admin
    }

    // MARK: - Visibilità sezioni

    /// "Dettagli Evento" ha sempre data e location → sempre visibile.
    private var hasDettagliContent: Bool { true }

    /// "Partecipanti & Gruppi" è visibile se c'è almeno un campo compilato
    /// oppure se l'utente è admin (vede i placeholder).
    private var hasPartecipantiContent: Bool {
        isAdmin
            || event.maxParticipants != nil
            || (event.isTeamEvent && (event.minPeoplePerGroup != nil || event.maxPeoplePerGroup != nil))
    }

    /// "Regolamento & Requisiti" è visibile se c'è almeno un campo compilato
    /// oppure se l'utente è admin.
    private var hasRegolamentoContent: Bool {
        isAdmin
            || event.weightLimit != nil
            || event.raceDuration != nil
            || event.maxStintDuration != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Hero ────────────────────────────────────────────
                        heroCard

                        // ── Pulsanti Live ────────────────────────────────────
                        liveActionsSection

                        // ── Immagine circuito ────────────────────────────────
                        circuitImageSection

                        // ── Descrizione ─────────────────────────────────────
                        let descText = event.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if isAdmin || !descText.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "text.alignleft")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.kartAccent)
                                    Text("DESCRIZIONE")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.kartAccent)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 12)

                                if descText.isEmpty {
                                    // Placeholder visibile solo all'admin
                                    HStack(spacing: 6) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 12))
                                            .foregroundColor(.kartDim)
                                        Text("Nessuna descrizione — modifica l'evento per aggiungerne una.")
                                            .font(.system(size: 13, weight: .regular))
                                            .foregroundColor(.kartDim)
                                            .italic()
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.bottom, 14)
                                } else {
                                    Text(descText)
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.white.opacity(0.88))
                                        .lineSpacing(5)
                                        .padding(.horizontal, 14)
                                        .padding(.bottom, 14)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.kartPanel)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        descText.isEmpty
                                            ? Color.kartAccent.opacity(0.2)
                                            : Color.white.opacity(0.05),
                                        lineWidth: 1
                                    )
                            )
                        }

                        // ── Dettagli principali ─────────────────────────────
                        infoSection(title: "Dettagli Evento", icon: "calendar") {
                            infoRow(label: "Data e Ora", value: event.formattedDate, icon: "calendar")
                            let locParts = event.location.components(separatedBy: " - ")
                            if locParts.count >= 2 {
                                infoRow(label: "Pista", value: locParts[0], icon: "flag.checkered")
                                infoRow(label: "Luogo", value: locParts[1...].joined(separator: " - "), icon: "mappin.and.ellipse")
                            } else {
                                if let k = kartodromoVM.kartodromi.first(where: { $0.nome == event.location }) {
                                    infoRow(label: "Pista", value: k.nome, icon: "flag.checkered")
                                    infoRow(label: "Luogo", value: k.luogo, icon: "mappin.and.ellipse")
                                } else {
                                    infoRow(label: "Pista / Luogo", value: event.location, icon: "mappin.and.ellipse")
                                }
                            }
                            if let deadline = event.registrationDeadline, !deadline.isEmpty {
                                deadlineRow(deadline: deadline, status: event.deadlineStatus)
                            }
                            let priceLabel = event.isTeamEvent ? "Prezzo per squadra" : "Prezzo"
                            if let cost = event.registrationCost {
                                infoRow(label: priceLabel, value: "€ \(String(format: "%.2f", cost))", icon: "eurosign")
                            } else if isAdmin {
                                infoRow(label: priceLabel, value: "Non definito", icon: "eurosign", dimmed: true)
                            }

                            if let kartType = event.kart, !kartType.isEmpty {
                                infoRow(label: "Kart", value: kartType, icon: "steeringwheel")
                            } else if isAdmin {
                                infoRow(label: "Kart", value: "Non definito", icon: "steeringwheel", dimmed: true)
                            }
                        }

                        // ── Partecipanti ────────────────────────────────────
                        if hasPartecipantiContent {
                            infoSection(title: "Partecipanti & Gruppi", icon: "person.3") {
                                let partLabel = event.isTeamEvent ? "Max Squadre" : "Max Partecipanti"
                                let partIcon = event.isTeamEvent ? "person.3.fill" : "person.fill"
                                if let max = event.maxParticipants {
                                    infoRow(label: partLabel, value: "\(max)", icon: partIcon)
                                } else if isAdmin {
                                    infoRow(label: partLabel, value: "Non definito", icon: partIcon, dimmed: true)
                                }
                                if event.isTeamEvent {
                                    if let minP = event.minPeoplePerGroup {
                                        infoRow(label: "Min Persone per Squadra", value: "\(minP)", icon: "person.2")
                                    }
                                    if let maxP = event.maxPeoplePerGroup {
                                        infoRow(label: "Max Persone per Squadra", value: "\(maxP)", icon: "person.2.fill")
                                    }
                                }
                            }
                        }

                        // ── Regolamento & Requisiti ───────────────────────
                        if hasRegolamentoContent {
                            infoSection(title: "Regolamento & Requisiti", icon: "list.clipboard") {
                                if let weight = event.weightLimit {
                                    infoRow(label: "Peso Minimo", value: "\(String(format: "%.1f", weight)) kg", icon: "scalemass")
                                } else if isAdmin {
                                    infoRow(label: "Peso Minimo", value: "Non definito", icon: "scalemass", dimmed: true)
                                }
                                if let dur = event.raceDuration {
                                    infoRow(label: "Durata Gara", value: "\(dur) min", icon: "clock")
                                }
                                if let stint = event.maxStintDuration {
                                    infoRow(label: "Max Stint", value: "\(stint) min", icon: "stopwatch")
                                }
                            }
                        }

                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Dettaglio Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .onAppear {
            kartodromoVM.fetchActive(serverURL: server.httpURL, token: authState.currentToken)
            Task { await fetchEventDetails() }
        }
        .fullScreenCover(isPresented: $showLive) {
            LiveRootView(server: server, event: localEvent)
                .environmentObject(authState)
        }
    }

    // MARK: - Live Actions Section

    @ViewBuilder
    private var liveActionsSection: some View {
        // Il director/admin vede sempre i pulsanti di controllo gara
        // Gli utenti iscritti vedono "Entra in Live" solo se la gara è avviata
        let canControl = isDirectorOrAdmin
        let isStarted = localEvent.status == "started"
        let isFinished = localEvent.status == "finished"

        if canControl || isStarted {
            VStack(spacing: 10) {
                // Pulsante Avvia / Termina (solo director/admin)
                if canControl {
                    if !isFinished {
                        Button(action: {
                            let newStatus = isStarted ? "finished" : "started"
                            Task { await toggleEventStatus(to: newStatus) }
                        }) {
                            HStack(spacing: 10) {
                                if isUpdatingStatus {
                                    ProgressView().tint(isStarted ? .red : .black).scaleEffect(0.85)
                                } else {
                                    Image(systemName: isStarted ? "stop.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 18))
                                    Text(isStarted ? "Termina Gara" : "Avvia Gara")
                                        .font(.system(size: 15, weight: .bold))
                                }
                            }
                            .foregroundColor(isStarted ? .red : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isStarted ? Color.red.opacity(0.15) : Color.kartAccent)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isStarted ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .disabled(isUpdatingStatus)
                    } else if isAdmin {
                        // Pulsante Ripristina per l'Admin
                        Button(action: {
                            Task { await toggleEventStatus(to: "scheduled") }
                        }) {
                            HStack(spacing: 10) {
                                if isUpdatingStatus {
                                    ProgressView().tint(.orange).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "arrow.counterclockwise.circle.fill")
                                        .font(.system(size: 18))
                                    Text("Ripristina a 'Programmata'")
                                        .font(.system(size: 15, weight: .bold))
                                }
                            }
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .disabled(isUpdatingStatus)
                    }
                }

                // Pulsante Entra in Live (tutti se gara avviata)
                if isStarted {
                    Button(action: { showLive = true }) {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Color.red).frame(width: 8, height: 8)
                            }
                            Text("Entra in Live")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(
                                colors: [Color.red.opacity(0.8), Color.orange.opacity(0.6)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                    }
                }

                if let err = statusError {
                    Text(err).font(.system(size: 12)).foregroundColor(.red)
                }

                if isFinished {
                    HStack(spacing: 6) {
                        Image(systemName: "checkered.flag")
                        Text("Gara terminata")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.kartDim)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.kartPanel)
                    .cornerRadius(10)
                }
            }
        }
    }

    @MainActor
    private func toggleEventStatus(to newStatus: String) async {
        guard let httpURL = server.httpURL,
              let token = authState.currentToken else { return }
        isUpdatingStatus = true
        statusError = nil
        do {
            // Costruisce l'URL corretto: la base senza /api
            let base = httpURL.absoluteString.replacingOccurrences(of: "/api", with: "")
            guard let fullURL = URL(string: "\(base)/events/\(localEvent.id)/status") else { return }
            var req = URLRequest(url: fullURL)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["status": newStatus])
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
                statusError = msg
            } else {
                // Aggiorna localEvent con il nuovo status (RaceEvent è Codable: ricrea la struct)
                localEvent = RaceEvent(
                    id: localEvent.id, title: localEvent.title,
                    eventDate: localEvent.eventDate,
                    registrationDeadline: localEvent.registrationDeadline,
                    daysBeforeDeadline: localEvent.daysBeforeDeadline,
                    location: localEvent.location,
                    maxParticipants: localEvent.maxParticipants,
                    minPeoplePerGroup: localEvent.minPeoplePerGroup,
                    maxPeoplePerGroup: localEvent.maxPeoplePerGroup,
                    registrationCost: localEvent.registrationCost,
                    weightLimit: localEvent.weightLimit,
                    kart: localEvent.kart,
                    description: localEvent.description,
                    raceDuration: localEvent.raceDuration,
                    maxStintDuration: localEvent.maxStintDuration,
                    createdAt: localEvent.createdAt,
                    status: newStatus
                )
            }
        } catch {
            statusError = error.localizedDescription
        }
        isUpdatingStatus = false
    }

    @MainActor
    private func fetchEventDetails() async {
        guard let httpURL = server.httpURL,
              let token = authState.currentToken else { return }
        
        do {
            let base = httpURL.absoluteString.replacingOccurrences(of: "/api", with: "")
            guard let fullURL = URL(string: "\(base)/events/\(localEvent.id)") else { return }
            var req = URLRequest(url: fullURL)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let updatedEvent = try? JSONDecoder().decode(RaceEvent.self, from: data) {
                    localEvent = updatedEvent
                }
            }
        } catch {
            print("Errore aggiornamento stato evento:", error)
        }
    }


    // MARK: - Circuit Image Section

    @ViewBuilder
    private var circuitImageSection: some View {
        // Trova il kartodromo corrispondente all'evento
        let kartodromo: Kartodromo? = {
            let locParts = event.location.components(separatedBy: " - ")
            let trackName = locParts.first ?? event.location
            return kartodromoVM.kartodromi.first(where: { $0.nome == trackName || $0.nome == event.location })
        }()

        if let k = kartodromo, let imageUrl = k.imageUrl {
            // Costruisce l'URL completo (il server serve /static/... dalla DATA_DIR)
            let baseURL = server.httpURL?.absoluteString
                .replacingOccurrences(of: "/api", with: "") ?? ""
            let fullURL = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + imageUrl)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.kartAccent)
                    Text("GRAFICA CIRCUITO")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    Spacer()
                    Text(k.nome.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartDim)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.kartAccent.opacity(0.08))

                if let url = fullURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(0)
                        case .failure:
                            HStack {
                                Image(systemName: "photo.slash")
                                    .foregroundColor(.kartDim)
                                Text("Immagine non disponibile")
                                    .font(.caption)
                                    .foregroundColor(.kartDim)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        case .empty:
                            ProgressView()
                                .tint(.kartAccent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .background(Color.kartPanel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.kartAccent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                        .lineLimit(3)
                }
            }

            Divider()
                .background(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                heroStat(value: event.formattedDate, icon: "calendar")

                // Costo: mostrato sempre se presente; se assente, solo l'admin vede "—"
                if let cost = event.registrationCost {
                    Spacer()
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.1))
                    Spacer()
                    heroStat(value: "€ \(String(format: "%.0f", cost))", icon: "eurosign.circle.fill")
                } else if isAdmin {
                    Spacer()
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.1))
                    Spacer()
                    heroStat(value: "—", icon: "eurosign.circle.fill")
                }

                Spacer()
                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.1))
                Spacer()
                let typeValue = event.isTeamEvent ? "GARA\nA SQUADRE" : "GARA\nINDIVIDUALE"
                let typeIcon = event.isTeamEvent ? "person.3.fill" : "person.fill"
                heroStat(value: typeValue, icon: typeIcon)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.kartPanel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            LinearGradient(
                                colors: [Color.kartAccent.opacity(0.5), Color.kartAccent.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
    }

    private func heroStat(value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.kartAccent)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Info section

    private func infoSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Intestazione sezione
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.kartAccent.opacity(0.08))

            VStack(spacing: 0) {
                content()
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
    }

    private func infoRow(label: String, value: String, icon: String, dimmed: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(dimmed ? .kartDim.opacity(0.5) : .kartAccent)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.kartDim)
                .frame(maxWidth: 160, alignment: .leading)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(dimmed ? .kartDim : .white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
                .background(Color.white.opacity(0.05))
                .padding(.leading, 44)
        }
    }

    /// Riga dedicata alla deadline con colore dinamico in base allo stato.
    /// Ogni branch del switch restituisce direttamente la view (pattern @ViewBuilder corretto).
    @ViewBuilder
    private func deadlineRow(deadline: String, status: RaceEvent.DeadlineStatus) -> some View {
        switch status {
        case .passed:
            infoRowColored(
                label: "Iscrizioni Chiuse",
                value: formattedDeadline(deadline),
                icon: "clock.badge.exclamationmark.fill",
                accentColor: Color.red
            )
        case .approaching:
            infoRowColored(
                label: "Scadenza Iscrizioni",
                value: formattedDeadline(deadline),
                icon: "clock.badge.exclamationmark",
                accentColor: Color.yellow
            )
        default:
            infoRowColored(
                label: "Scadenza Iscrizioni",
                value: formattedDeadline(deadline),
                icon: "clock.badge.exclamationmark",
                accentColor: Color.kartAccent
            )
        }
    }

    /// Variante con colore accent personalizzato per icona e testo valore (es. deadline colorata)
    private func infoRowColored(label: String, value: String, icon: String, accentColor: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(accentColor)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.kartDim)
                .frame(maxWidth: 160, alignment: .leading)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accentColor)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
                .background(Color.white.opacity(0.05))
                .padding(.leading, 44)
        }
    }

    // MARK: - Helpers

    private func formattedDeadline(_ raw: String) -> String {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        
        let df1 = DateFormatter()
        df1.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        let df2 = DateFormatter()
        df2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        fmt.locale = Locale(identifier: "it_IT")

        if let d = isoFull.date(from: raw) { return fmt.string(from: d) }
        if let d = isoBasic.date(from: raw) { return fmt.string(from: d) }
        if let d = df1.date(from: raw) { return fmt.string(from: d) }
        if let d = df2.date(from: raw) { return fmt.string(from: d) }
        return raw
    }
}
