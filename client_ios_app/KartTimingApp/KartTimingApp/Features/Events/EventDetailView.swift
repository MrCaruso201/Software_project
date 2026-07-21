import SwiftUI

struct EventDetailView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authState: AuthState
    let server: DiscoveredServer
    let event: RaceEvent
    @StateObject private var kartodromoVM = KartodromoViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Hero ────────────────────────────────────────────
                        heroCard

                        // ── Descrizione ─────────────────────────────────────
                        let isAdmin = authState.currentUser?.role.canManageUsers == true
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
                                infoRow(label: "Scadenza Iscrizioni", value: formattedDeadline(deadline), icon: "clock.badge.exclamationmark")
                            }
                            let priceLabel = event.isTeamEvent ? "Prezzo per squadra" : "Prezzo"
                            if let cost = event.registrationCost {
                                infoRow(label: priceLabel, value: "€ \(String(format: "%.2f", cost))", icon: "eurosign")
                            } else {
                                infoRow(label: priceLabel, value: "Non definito", icon: "eurosign", dimmed: true)
                            }
                            
                            if let kartType = event.kart, !kartType.isEmpty {
                                infoRow(label: "Kart", value: kartType, icon: "steeringwheel")
                            } else {
                                infoRow(label: "Kart", value: "Non definito", icon: "steeringwheel", dimmed: true)
                            }
                        }

                        // ── Partecipanti ────────────────────────────────────
                        infoSection(title: "Partecipanti & Gruppi", icon: "person.3") {
                            let partLabel = event.isTeamEvent ? "Max Squadre" : "Max Partecipanti"
                            let partIcon = event.isTeamEvent ? "person.3.fill" : "person.fill"
                            if let max = event.maxParticipants {
                                infoRow(label: partLabel, value: "\(max)", icon: partIcon)
                            } else {
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

                        // ── Regolamento & Requisiti ───────────────────────
                        infoSection(title: "Regolamento & Requisiti", icon: "list.clipboard") {
                            if let weight = event.weightLimit {
                                infoRow(label: "Peso Minimo", value: "\(String(format: "%.1f", weight)) kg", icon: "scalemass")
                            } else {
                                infoRow(label: "Peso Minimo", value: "Nessun limite", icon: "scalemass", dimmed: true)
                            }
                            if let dur = event.raceDuration {
                                infoRow(label: "Durata Gara", value: "\(dur) min", icon: "clock")
                            }
                            if let stint = event.maxStintDuration {
                                infoRow(label: "Max Stint", value: "\(stint) min", icon: "stopwatch")
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
                Spacer()
                Divider()
                    .frame(height: 36)
                    .background(Color.white.opacity(0.1))
                Spacer()
                if let cost = event.registrationCost {
                    heroStat(value: "€ \(String(format: "%.0f", cost))", icon: "eurosign.circle.fill")
                } else {
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
