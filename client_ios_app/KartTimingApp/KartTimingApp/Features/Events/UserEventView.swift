import SwiftUI

/// Vista dedicata all'evento per utenti normali (e raceDirector).
/// NavigationStack + TabView con 2 tab: Info, Iscrizione.
struct UserEventView: View {
    let server: DiscoveredServer
    let event: RaceEvent
    @ObservedObject var viewModel: EventsViewModel

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var localEvent: RaceEvent

    // Sheets iscrizione
    enum ActiveSheet: Identifiable {
        case register
        case editTeam(EventRegistrationResponse)
        case viewTeam(EventRegistrationResponse)
        case payment
        var id: String {
            switch self {
            case .register:      return "register"
            case .editTeam:      return "editTeam"
            case .viewTeam:      return "viewTeam"
            case .payment:       return "payment"
            }
        }
    }
    @State private var activeSheet: ActiveSheet? = nil

    // Liberatoria
    @State private var hasSignedRelease = false
    @State private var showLive = false
    @State private var showLiveAsSpectator = false

    init(server: DiscoveredServer, event: RaceEvent, viewModel: EventsViewModel) {
        self.server = server
        self.event = event
        self.viewModel = viewModel
        _localEvent = State(initialValue: event)
    }

    // MARK: - Computed helpers

    private var reg: EventRegistrationResponse? { viewModel.userRegistrations[localEvent.id] }
    private var status: String? { reg?.status }
    private var isPending: Bool    { status == "pending_payment" }
    private var isConfirmed: Bool  { status == "confirmed" }
    private var isWaitlist: Bool   { status == "waitlist" }
    private var isRegistered: Bool { status != nil }
    private var deadlinePassed: Bool     { localEvent.isDeadlinePassed }
    private var deadlineApproaching: Bool { localEvent.isDeadlineApproaching }

    private var registrationBadgeLabel: String {
        if isPending    { return "IN ATTESA PAGAMENTO" }
        if isConfirmed  { return "CONFERMATA" }
        if isWaitlist   { return "IN LISTA D'ATTESA" }
        if isRegistered { return "ISCRITTO" }
        return "NON ISCRITTO"
    }
    private var registrationBadgeColor: Color {
        if isPending   { return .kartWarning }
        if isConfirmed { return .kartSuccess }
        if isWaitlist  { return .purple }
        return .gray
    }

    var body: some View {
        NavigationStack {
            TabView {
                // ── Tab 1: Info ───────────────────────────────────────────
                EventDetailContentView(
                    server: server,
                    event: $localEvent,
                    viewModel: viewModel
                )
                .tabItem { Label("Info", systemImage: "info.circle.fill") }

                // ── Tab 2: Iscrizione ─────────────────────────────────────
                registrationTab
                    .tabItem { Label("Iscrizione", systemImage: "pencil.and.list.clipboard") }
            }
            .tint(.kartAccent)
            .navigationTitle(localEvent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                        .font(.system(size: 14, weight: .semibold))
                }
                ToolbarItem(placement: .principal) {
                    Text(registrationBadgeLabel)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(registrationBadgeColor)
                }
            }
        }
        .sheet(item: $activeSheet, onDismiss: refreshRegistrations) { sheetType in
            switch sheetType {
            case .register:
                EventRegistrationSheetView(server: server, viewModel: viewModel, event: localEvent)
                    .environmentObject(authState)
            case .editTeam(let registration):
                EventTeamEditSheetView(server: server, viewModel: viewModel, event: localEvent, registration: registration)
                    .environmentObject(authState)
            case .viewTeam(let registration):
                TeamMemberView(server: server, viewModel: viewModel, event: localEvent, registration: registration)
                    .environmentObject(authState)
            case .payment:
                PaymentInfoSheetView(event: localEvent)
                    .environmentObject(authState)
            }
        }
        .fullScreenCover(isPresented: $showLive) {
            LiveRootView(server: server, event: localEvent, isUserRegistered: true)
                .environmentObject(authState)
        }
        .fullScreenCover(isPresented: $showLiveAsSpectator) {
            LiveRootView(server: server, event: localEvent, isUserRegistered: false)
                .environmentObject(authState)
        }
        .onAppear {
            refreshRegistrations()
            Task { await fetchReleaseStatus() }
        }
    }

    // MARK: - Iscrizione Tab

    @ViewBuilder
    private var registrationTab: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {

                    // ── Entra in Live (gara avviata) ───────────────────────
                    if localEvent.status == "started" {
                        Button(action: {
                            if isRegistered { showLive = true }
                            else { showLiveAsSpectator = true }
                        }) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(Color.red).frame(width: 8, height: 8)
                                }
                                Text("Entra in Live")
                                    .font(.system(size: 15, weight: .bold))
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.8), Color.orange.opacity(0.6)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }

                    // ── Banner deadline ────────────────────────────────
                    if !isRegistered {
                        if deadlinePassed {
                            deadlineBanner(
                                icon: "clock.badge.exclamationmark.fill",
                                text: "Iscrizioni chiuse — verrai messo in lista d'attesa",
                                bg: Color.red.opacity(0.25),
                                stroke: Color.red.opacity(0.5),
                                fg: .white
                            )
                        } else if deadlineApproaching, let dl = localEvent.deadlineObject {
                            let daysLeft = max(0, Int(dl.timeIntervalSince(Date()) / 86400))
                            let hoursLeft = max(0, Int(dl.timeIntervalSince(Date()) / 3600))
                            let timeLabel = daysLeft > 0
                                ? "\(daysLeft) giorn\(daysLeft == 1 ? "o" : "i")"
                                : "\(hoursLeft) or\(hoursLeft == 1 ? "a" : "e")"
                            deadlineBanner(
                                icon: "clock.badge.exclamationmark",
                                text: "Iscrizioni in scadenza: \(timeLabel) rimastr\(daysLeft == 1 || hoursLeft == 1 ? "o" : "i")",
                                bg: Color.yellow.opacity(0.85),
                                stroke: .clear,
                                fg: .black
                            )
                        }
                    }

                    // ── Stato iscrizione ───────────────────────────────
                    registrationStatusCard

                    // ── Azione principale ──────────────────────────────
                    mainActionButton

                    // ── Pagamento pending ──────────────────────────────
                    if isPending {
                        Button {
                            activeSheet = .payment
                        } label: {
                            Text("In attesa di pagamento: procedi")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.yellow)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    }

                    // ── Waitlist info ──────────────────────────────────
                    if isWaitlist && !event.isTeamEvent {
                        Text("Posti attualmente esauriti. Sei in lista d'attesa.")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.purple.opacity(0.25))
                            .foregroundColor(.purple)
                            .cornerRadius(10)
                    }

                    // ── Liberatoria (solo se iscritto e configurata) ────
                    if isRegistered,
                       let releaseText = localEvent.releaseFormText,
                       !releaseText.isEmpty {
                        NavigationLink(destination:
                            ReleaseFormSignView(
                                server: server,
                                event: localEvent,
                                onSignComplete: { Task { await fetchReleaseStatus() } }
                            ).environmentObject(authState)
                        ) {
                            HStack(spacing: 10) {
                                Image(systemName: "signature")
                                    .font(.system(size: 16))
                                Text(hasSignedRelease
                                     ? "Visualizza/Modifica Liberatoria"
                                     : "Firma Liberatoria")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .foregroundColor(hasSignedRelease ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(hasSignedRelease ? Color.green : Color.kartAccent)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Status Card

    @ViewBuilder
    private var registrationStatusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text("STATO ISCRIZIONE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.kartAccent.opacity(0.08))

            HStack(spacing: 14) {
                Circle()
                    .fill(registrationBadgeColor)
                    .frame(width: 10, height: 10)
                Text(registrationBadgeLabel)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(registrationBadgeColor)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.kartBorder(opacity: 0.05), lineWidth: 1)
        )
    }

    // MARK: - Main Action Button

    @ViewBuilder
    private var mainActionButton: some View {
        if authState.currentUser?.role == .raceDirector {
            // raceDirector: nessuna azione iscrizione
            EmptyView()
        } else if !isRegistered {
            if localEvent.status == "started" {
                // Evento già in corso: non si può più iscrivere
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                    Text("Evento Iniziato")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.kartDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.kartPanel)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.kartBorder(opacity: 0.08), lineWidth: 1)
                )
            } else {
                // Evento non ancora iniziato: mostra il pulsante Iscriviti
                Button {
                    activeSheet = .register
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: deadlinePassed ? "clock.badge.exclamationmark" : "pencil.and.list.clipboard")
                        Text(deadlinePassed ? "Mettiti in Lista d'Attesa" : "Iscriviti")
                            .font(.system(size: 15, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.kartAction)
                    .cornerRadius(12)
                }
            }
        } else if let registration = reg, !isConfirmed {
            if event.isTeamEvent && registration.isTeamLeader {
                Button {
                    activeSheet = .editTeam(registration)
                } label: {
                    actionLabel("Modifica Squadra", icon: "pencil.circle.fill", bg: .kartPanel)
                }
            } else if event.isTeamEvent && !registration.isTeamLeader {
                Button {
                    activeSheet = .viewTeam(registration)
                } label: {
                    actionLabel("Vedi Squadra", icon: "person.3.fill", bg: .kartPanel)
                }
            } else {
                Button {
                    if let token = authState.currentToken {
                        viewModel.unregisterFromEvent(
                            serverURL: server.httpURL, eventId: localEvent.id, token: token
                        ) { _, _ in refreshRegistrations() }
                    }
                } label: {
                    actionLabel("Annulla Iscrizione", icon: "xmark.circle.fill", bg: .kartRed.opacity(0.08), destructive: true)
                }
            }
        } else if isConfirmed {
            if let registration = reg, event.isTeamEvent, registration.isTeamLeader {
                Button {
                    activeSheet = .editTeam(registration)
                } label: {
                    actionLabel("Modifica Squadra", icon: "pencil.circle.fill", bg: .kartPanel)
                }
            } else if let registration = reg, event.isTeamEvent, !registration.isTeamLeader {
                Button {
                    activeSheet = .viewTeam(registration)
                } label: {
                    actionLabel("Vedi Squadra", icon: "person.3.fill", bg: .kartPanel)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Iscrizione Confermata")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundColor(.kartSuccess)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.kartSuccess.opacity(0.12))
                .cornerRadius(12)
            }
        } else if isWaitlist {
            if let registration = reg, event.isTeamEvent, registration.isTeamLeader {
                Button {
                    activeSheet = .editTeam(registration)
                } label: {
                    actionLabel("Modifica Squadra", icon: "pencil.circle.fill", bg: .kartPanel)
                }
            } else if let registration = reg, event.isTeamEvent, !registration.isTeamLeader {
                Button {
                    activeSheet = .viewTeam(registration)
                } label: {
                    actionLabel("Vedi Squadra", icon: "person.3.fill", bg: .kartPanel)
                }
            }
        }
    }

    // MARK: - Helpers

    private func actionLabel(_ text: String, icon: String, bg: Color, destructive: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
                .font(.system(size: 15, weight: .bold))
        }
        .foregroundColor(destructive ? .kartRed : .kartForeground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(bg)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1))
    }

    private func deadlineBanner(icon: String, text: String, bg: Color, stroke: Color, fg: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(text)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .foregroundColor(fg)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bg)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(stroke, lineWidth: 1)
        )
        .cornerRadius(10)
    }

    private func refreshRegistrations() {
        if let token = authState.currentToken {
            viewModel.fetchUserRegistrations(serverURL: server.httpURL, token: token)
        }
    }

    @MainActor
    private func fetchReleaseStatus() async {
        guard let httpURL = server.httpURL,
              let token = authState.currentToken else { return }
        do {
            let base = httpURL.absoluteString.replacingOccurrences(of: "/api", with: "")
            guard let regURL = URL(string: "\(base)/events/registrations/me") else { return }
            var req = URLRequest(url: regURL)
            req.httpMethod = "GET"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, resp) = try await NetworkService.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                if let regs = try? JSONDecoder().decode([EventRegistrationResponse].self, from: data) {
                    if let myReg = regs.first(where: { $0.eventId == localEvent.id }) {
                        hasSignedRelease = myReg.hasSignedRelease ?? false
                    }
                }
            }
        } catch {
            print("Errore fetch release status:", error)
        }
    }
}

