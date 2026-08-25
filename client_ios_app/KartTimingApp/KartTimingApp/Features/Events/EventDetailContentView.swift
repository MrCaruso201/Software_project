import SwiftUI

/// Contenuto riutilizzabile della vista dettaglio evento.
/// Usato sia da `AdminEventView` che da `UserEventView` nella tab "Info",
/// e dalla standalone `EventDetailView` per i deep link da notifiche.
struct EventDetailContentView: View {
    let server: DiscoveredServer
    @Binding var event: RaceEvent
    @ObservedObject var viewModel: EventiViewModel

    @EnvironmentObject var authState: AuthState
    @StateObject private var kartodromoVM = KartodromoViewModel()

    @State private var showLive = false
    @State private var isRegistered = false
    @State private var hasSignedRelease = false

    // MARK: - Computed

    private var isAdmin: Bool {
        authState.currentUser?.role.canManageUsers == true
    }

    private var isDirectorOrAdmin: Bool {
        let role = authState.currentUser?.role
        return role == .raceDirector || role == .admin
    }

    private var hasPartecipantiContent: Bool {
        event.maxParticipants != nil
            || (event.isTeamEvent && (event.minPeoplePerGroup != nil || event.maxPeoplePerGroup != nil))
    }

    private var hasRegolamentoContent: Bool {
        event.weightLimit != nil
            || event.raceDuration != nil
            || event.maxStintDuration != nil
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // -- Hero
                    heroCard

                    // -- Entra in Live / badge terminata
                    liveEntrySection

                    // -- Immagine circuito
                    circuitImageSection

                    // -- Descrizione
                    let descText = event.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !descText.isEmpty {
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

                            Text(descText)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundColor(.white.opacity(0.88))
                                .lineSpacing(5)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 14)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.kartPanel)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        )
                    }

                    // -- Dettagli principali
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
                        }
                        if let kartType = event.kart, !kartType.isEmpty {
                            infoRow(label: "Kart", value: kartType, icon: "steeringwheel")
                        }
                    }

                    // -- Partecipanti
                    if hasPartecipantiContent {
                        infoSection(title: "Partecipanti & Gruppi", icon: "person.3") {
                            let partLabel = event.isTeamEvent ? "Max Squadre" : "Max Partecipanti"
                            let partIcon = event.isTeamEvent ? "person.3.fill" : "person.fill"
                            if let max = event.maxParticipants {
                                infoRow(label: partLabel, value: "\(max)", icon: partIcon)
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

                    // -- Regolamento & Requisiti
                    if hasRegolamentoContent {
                        infoSection(title: "Regolamento & Requisiti", icon: "list.clipboard") {
                            if let weight = event.weightLimit {
                                infoRow(label: "Peso Minimo", value: "\(String(format: "%.1f", weight)) kg", icon: "scalemass")
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
        .onAppear {
            kartodromoVM.fetchActive(serverURL: server.httpURL, token: authState.currentToken)
            Task { await fetchEventDetails() }
        }
        .fullScreenCover(isPresented: $showLive) {
            LiveRootView(server: server, event: event)
                .environmentObject(authState)
        }
    }

    // MARK: - Live Entry Section

    @ViewBuilder
    private var liveEntrySection: some View {
        let isStarted = event.status == "started"
        let isFinished = event.status == "finished"

        if isStarted && (isDirectorOrAdmin || isRegistered) {
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
        } else if isFinished {
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

    // MARK: - Fetch Details

    @MainActor
    private func fetchEventDetails() async {
        guard let httpURL = server.httpURL,
              let token = authState.currentToken else { return }
        do {
            let base = httpURL.absoluteString.replacingOccurrences(of: "/api", with: "")
            guard let fullURL = URL(string: "\(base)/events/\(event.id)") else { return }
            var req = URLRequest(url: fullURL)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let updated = try? JSONDecoder().decode(RaceEvent.self, from: data) {
                    event = updated
                }
            }

            guard let regURL = URL(string: "\(base)/events/registrations/me") else { return }
            var regReq = URLRequest(url: regURL)
            regReq.httpMethod = "GET"
            regReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (regData, regResp) = try await URLSession.shared.data(for: regReq)
            if let http = regResp as? HTTPURLResponse, http.statusCode == 200 {
                if let regs = try? JSONDecoder().decode([EventRegistrationResponse].self, from: regData) {
                    if let myReg = regs.first(where: { $0.eventId == event.id }) {
                        isRegistered = true
                        hasSignedRelease = myReg.hasSignedRelease ?? false
                    } else {
                        isRegistered = false
                        hasSignedRelease = false
                    }
                }
            }
        } catch {
            print("Errore fetch event details:", error)
        }
    }

    // MARK: - Circuit Image Section

    @ViewBuilder
    private var circuitImageSection: some View {
        let kartodromo: Kartodromo? = {
            let locParts = event.location.components(separatedBy: " - ")
            let trackName = locParts.first ?? event.location
            return kartodromoVM.kartodromi.first(where: { $0.nome == trackName || $0.nome == event.location })
        }()

        if let k = kartodromo, let imageUrl = k.imageUrl {
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
                                Image(systemName: "photo.slash").foregroundColor(.kartDim)
                                Text("Immagine non disponibile").font(.caption).foregroundColor(.kartDim)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        case .empty:
                            ProgressView().tint(.kartAccent).frame(maxWidth: .infinity).padding(.vertical, 24)
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
                RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
    }

    // MARK: - Hero Card

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

            Divider().background(Color.white.opacity(0.08))

            HStack(spacing: 0) {
                heroStat(value: event.formattedDate, icon: "calendar")

                if let cost = event.registrationCost {
                    Spacer()
                    Divider().frame(height: 36).background(Color.white.opacity(0.1))
                    Spacer()
                    heroStat(value: "€ \(String(format: "%.0f", cost))", icon: "eurosign.circle.fill")
                }

                Spacer()
                Divider().frame(height: 36).background(Color.white.opacity(0.1))
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
            Image(systemName: icon).font(.system(size: 12)).foregroundColor(.kartAccent)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Info Section

    private func infoSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
            VStack(spacing: 0) { content() }
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
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
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 44)
        }
    }

    @ViewBuilder
    private func deadlineRow(deadline: String, status: RaceEvent.DeadlineStatus) -> some View {
        switch status {
        case .passed:
            infoRowColored(label: "Iscrizioni Chiuse", value: formattedDeadline(deadline),
                           icon: "clock.badge.exclamationmark.fill", accentColor: .red)
        case .approaching:
            infoRowColored(label: "Scadenza Iscrizioni", value: formattedDeadline(deadline),
                           icon: "clock.badge.exclamationmark", accentColor: .yellow)
        default:
            infoRowColored(label: "Scadenza Iscrizioni", value: formattedDeadline(deadline),
                           icon: "clock.badge.exclamationmark", accentColor: .kartAccent)
        }
    }

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
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 44)
        }
    }

    // MARK: - Helpers

    private func formattedDeadline(_ raw: String) -> String {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        let df1 = DateFormatter(); df1.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let df2 = DateFormatter(); df2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let fmt = DateFormatter()
        fmt.dateStyle = .medium; fmt.timeStyle = .none
        fmt.locale = Locale(identifier: "it_IT")
        if let d = isoFull.date(from: raw) { return fmt.string(from: d) }
        if let d = isoBasic.date(from: raw) { return fmt.string(from: d) }
        if let d = df1.date(from: raw) { return fmt.string(from: d) }
        if let d = df2.date(from: raw) { return fmt.string(from: d) }
        return raw
    }
}
