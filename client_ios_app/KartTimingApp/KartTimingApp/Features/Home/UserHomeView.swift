import SwiftUI

struct UserHomeView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = UserHomeViewModel()
    
    @State private var showNotifications = false
    @State private var liveEvent: RaceEvent? = nil
    @State private var liveEventUserIsRegistered: Bool = false
    
    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView().tint(.kartAccent).scaleEffect(1.3)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        profileCard
                        nextEventCard
                        
                        if authState.currentUser?.role.canManageUsers == true {
                            AdminUserSearchCard(server: server)
                                .environmentObject(authState)
                        }
                        
                        if viewModel.profile?.role == "user" {
                            myRegistrationsCard
                        }
                    }
                    .padding(16)
                }
                .refreshable {
                    await withCheckedContinuation { continuation in
                        viewModel.fetchData(serverURL: server.httpURL, token: authState.currentToken) {
                            continuation.resume()
                        }
                    }
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showNotifications = true
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.kartAccent)

                        if viewModel.unreadCount > 0 {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 16, height: 16)
                                Text(viewModel.unreadCount > 9 ? "9+" : "\(viewModel.unreadCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .offset(x: 8, y: -8)
                        }
                    }
                }
                .sheet(isPresented: $showNotifications) {
                    NotificationsPanelView(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            viewModel.fetchData(serverURL: server.httpURL, token: authState.currentToken)
        }
        .fullScreenCover(item: $liveEvent) { ev in
            LiveRootView(server: server, event: ev, isUserRegistered: liveEventUserIsRegistered)
                .environmentObject(authState)
        }
    }
    
    // MARK: - Profile Card
    private var profileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                if let profilePictureURL = viewModel.profile?.profilePictureURL,
                   let url = URL(string: server.httpURL?.absoluteString.replacingOccurrences(of: "/api", with: "") ?? "")?.appendingPathComponent(String(profilePictureURL.dropFirst())) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } else if phase.error != nil {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.kartAccent)
                        } else {
                            ProgressView()
                                .frame(width: 60, height: 60)
                        }
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.kartAccent)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let p = viewModel.profile {
                        let hasName = (p.firstName != nil && !p.firstName!.isEmpty) || (p.lastName != nil && !p.lastName!.isEmpty)
                        if hasName {
                            Text("\(p.firstName ?? "") \(p.lastName ?? "")")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("@\(p.username)")
                                .font(.subheadline)
                                .foregroundColor(.kartDim)
                        } else {
                            Text("@\(p.username)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("Utente")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                Spacer()
            }
            

        }
        .padding(16)
        .background(Color.kartPanel)
        .cornerRadius(12)
    }
    
    // MARK: - Next Event Card
    @ViewBuilder
    private var nextEventCard: some View {
        if let nextEvent = viewModel.events
            .filter({ ($0.dateObject ?? .distantFuture) >= Calendar.current.startOfDay(for: Date()) })
            .sorted(by: { ($0.dateObject ?? .distantFuture) < ($1.dateObject ?? .distantFuture) })
            .first, let eventDate = nextEvent.dateObject {
            
            let isRegistered = viewModel.registrations.contains { $0.eventId == nextEvent.id && $0.status == "confirmed" }
            
            if Calendar.current.isDateInToday(eventDate) {
                let isLive = nextEvent.status == "started"

                VStack(spacing: 8) {
                    // ── Riquadro info evento (tap → dettaglio) ────────────
                    Button {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("OpenEventDetail"),
                            object: nil,
                            userInfo: ["eventId": nextEvent.id]
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    if isLive {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 7, height: 7)
                                    }
                                    Text(isLive ? "LIVE ORA" : "EVENTO OGGI")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(isLive ? .red : (isRegistered ? .green : .red))
                                }
                                Text(nextEvent.title)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text(isLive ? "Tocca per i dettagli" : "Tocca per i dettagli")
                                    .font(.system(size: 12))
                                    .foregroundColor(.kartDim)
                            }
                            Spacer()
                            Image(systemName: isLive ? "flag.checkered" : "stopwatch.fill")
                                .font(.system(size: 30))
                                .foregroundColor(isLive ? .red : (isRegistered ? .green : .red))
                        }
                        .padding(16)
                        .background(
                            isLive
                                ? Color.red.opacity(0.08)
                                : Color.kartPanel
                        )
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isLive
                                        ? Color.red.opacity(0.4)
                                        : (isRegistered ? Color.green : Color.red).opacity(0.5),
                                    lineWidth: isLive ? 1.5 : 1
                                )
                        )
                        .shadow(
                            color: isLive ? Color.red.opacity(0.15) : .clear,
                            radius: 10, x: 0, y: 4
                        )
                    }
                    .buttonStyle(.plain)

                    // ── Pulsante Entra in Live (solo se gara avviata) ─────
                    if isLive {
                        Button {
                            liveEventUserIsRegistered = isRegistered
                            liveEvent = nextEvent
                        } label: {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle().fill(Color.red).frame(width: 8, height: 8)
                                }
                                Text("Entra in Live")
                                    .font(.system(size: 15, weight: .bold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 13)
                            .frame(maxWidth: .infinity)
                            .background(
                                LinearGradient(
                                    colors: [Color.red.opacity(0.85), Color.orange.opacity(0.65)],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }

            } else {
                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("OpenEventDetail"),
                        object: nil,
                        userInfo: ["eventId": nextEvent.id]
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "timer")
                                .foregroundColor(isRegistered ? .green : .kartAccent)
                            Text("PROSSIMO EVENTO")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(isRegistered ? .green : .kartAccent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.kartDim)
                        }
                        
                        Text(nextEvent.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            
                        let city = nextEvent.location.components(separatedBy: " - ").first ?? nextEvent.location
                        
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.kartDim)
                            Text(city)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.kartDim)
                                .lineLimit(1)
                        }
                        
                        HStack {
                            Text("- \(countdownString(to: eventDate))")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .background(Color.kartPanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke((isRegistered ? Color.green : Color.white).opacity(0.06), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func countdownString(to date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date))
        let months = components.month ?? 0
        let days = components.day ?? 0
        
        var text = ""
        if months > 0 {
            text += "\(months) mes\(months == 1 ? "e" : "i") "
        }
        if months > 0 && days > 0 {
            text += "e "
        }
        text += "\(days) giorn\(days == 1 ? "o" : "i")"
        return text
    }
    // MARK: - Le mie iscrizioni Card

    private var myRegistrationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ─────────────────────────────────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text("LE MIE ISCRIZIONI")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
                let upcomingCount = viewModel.registrations.filter { reg in
                    (viewModel.events.first(where: { ev in ev.id == reg.eventId })?.dateObject ?? .distantFuture) >= Date()
                }.count
                Text("\(upcomingCount)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.kartAccent.opacity(0.08))

            // Filtra solo gli eventi futuri (data >= oggi)
            let upcomingRegs = viewModel.registrations.filter { reg in
                (viewModel.events.first(where: { ev in ev.id == reg.eventId })?.dateObject ?? .distantFuture) >= Date()
            }

            if upcomingRegs.isEmpty {
                // Stato vuoto
                VStack(spacing: 12) {
                    Image(systemName: "flag.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.kartDim.opacity(0.4))
                    Text("Nessuna iscrizione")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.kartDim)
                    Text("Iscriviti a un evento dalla sezione \"Eventi\"")
                        .font(.system(size: 12))
                        .foregroundColor(.kartDim.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                // Lista iscrizioni ordinate per data evento
                let sorted = upcomingRegs.sorted { r0, r1 in
                    let d0 = viewModel.events.first(where: { $0.id == r0.eventId })?.dateObject ?? .distantFuture
                    let d1 = viewModel.events.first(where: { $0.id == r1.eventId })?.dateObject ?? .distantFuture
                    return d0 < d1
                }

                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, reg in
                        if let event = viewModel.events.first(where: { $0.id == reg.eventId }) {
                            registrationRow(reg: reg, event: event)

                            if idx < sorted.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 58)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func registrationRow(reg: EventRegistrationResponse, event: RaceEvent) -> some View {
        Button {
            NotificationCenter.default.post(
                name: NSNotification.Name("OpenEventDetail"),
                object: nil,
                userInfo: ["eventId": event.id]
            )
        } label: {
            HStack(spacing: 12) {
                // ── Icona status ─────────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(statusColor(reg.status).opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: statusIcon(reg.status))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(statusColor(reg.status))
                }

                // ── Info evento ──────────────────────────────────────────
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Data
                        if let date = event.dateObject {
                            Label(date.formatted(.dateTime.day().month(.abbreviated).year()),
                                  systemImage: "calendar")
                                .font(.system(size: 11))
                                .foregroundColor(.kartDim)
                        }

                        // Luogo
                        let city = event.location.components(separatedBy: " - ").first ?? event.location
                        Label(city, systemImage: "mappin.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.kartDim)
                            .lineLimit(1)
                    }

                    // Team name (se evento a squadre)
                    if let team = reg.teamName, !team.isEmpty {
                        Label(team, systemImage: "person.2.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.kartAccent.opacity(0.8))
                    }
                    
                    if reg.hasSignedRelease == true {
                        Label("Liberatoria Firmata", systemImage: "signature")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.green)
                    }
                }

                Spacer()

                // ── Badge status ─────────────────────────────────────────
                VStack(alignment: .trailing, spacing: 4) {
                    Text(statusLabel(reg.status))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor(reg.status))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor(reg.status).opacity(0.14))
                        .cornerRadius(5)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.kartDim)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers status

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "confirmed":       return .green
        case "pending_payment": return .orange
        case "waitlist":        return .purple
        default:                return .kartDim
        }
    }

    private func statusIcon(_ status: String) -> String {
        switch status {
        case "confirmed":       return "checkmark.circle.fill"
        case "pending_payment": return "exclamationmark.triangle.fill"
        case "waitlist":        return "clock.fill"
        default:                return "questionmark.circle"
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "confirmed":       return "CONFERMATA"
        case "pending_payment": return "DA PAGARE"
        case "waitlist":        return "LISTA ATTESA"
        default:                return status.uppercased()
        }
    }
}


