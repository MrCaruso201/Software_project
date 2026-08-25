import SwiftUI

struct EventiView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = EventiViewModel()
    
    @State private var searchText = ""
    @State private var expandedEventId: Int? = nil
    @EnvironmentObject var appEnv: AppEnvironment
    
    // Gestione Form (nuovo evento)
    enum ActiveSheet: Identifiable {
        case new
        var id: String { "new" }
    }
    @State private var activeSheet: ActiveSheet? = nil

    // Vista dedicata evento (fullScreenCover — non chiudibile con swipe)
    @State private var selectedEventToOpen: RaceEvent? = nil
    
    // Per i risultati (eventi passati)
    @StateObject private var analisiViewModel = AnalisiViewModel()
    @State private var eventForClassification: RaceEvent? = nil
    
    var filteredEvents: [RaceEvent] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return viewModel.events }
        return viewModel.events.filter { event in
            event.title.lowercased().contains(q) ||
            event.location.lowercased().contains(q) ||
            event.formattedDate.lowercased().contains(q)
        }
    }
    
    var todayEvents: [RaceEvent] {
        return filteredEvents
            .filter { Calendar.current.isDateInToday($0.dateObject ?? .distantPast) }
            .sorted { ($0.dateObject ?? .distantFuture) < ($1.dateObject ?? .distantFuture) }
    }

    var upcomingEvents: [RaceEvent] {
        let now = Date()
        return filteredEvents
            .filter { 
                let date = $0.dateObject ?? .distantFuture
                return date > now && !Calendar.current.isDateInToday(date)
            }
            .sorted { ($0.dateObject ?? .distantFuture) < ($1.dateObject ?? .distantFuture) }
    }
    
    var pastEvents: [RaceEvent] {
        let now = Date()
        return filteredEvents
            .filter { 
                let date = $0.dateObject ?? .distantFuture
                return date < now && !Calendar.current.isDateInToday(date)
            }
            .sorted { ($0.dateObject ?? .distantPast) > ($1.dateObject ?? .distantPast) }
    }
    
    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerBar
                
                if viewModel.isLoading {
                    Spacer()
                    ProgressView().tint(.kartAccent).scaleEffect(1.3)
                    Text("Caricamento eventi...")
                        .foregroundColor(.kartDim)
                        .font(.caption)
                        .padding(.top, 8)
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    Spacer()
                    Text(errorMessage)
                        .foregroundColor(.kartRed)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else if filteredEvents.isEmpty {
                    Spacer()
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.kartDim)
                    Text("Nessun evento trovato")
                        .foregroundColor(.kartDim)
                        .padding(.top, 8)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if !todayEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader("OGGI", icon: "calendar.circle")
                                    ForEach(todayEvents) { event in
                                        eventRow(event, isPast: false)
                                    }
                                }
                            }

                            if !upcomingEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader("IN PROGRAMMA", icon: "calendar.badge.clock")
                                        .padding(.top, todayEvents.isEmpty ? 0 : 10)
                                    ForEach(upcomingEvents) { event in
                                        eventRow(event, isPast: false)
                                    }
                                }
                            }
                            
                            if !pastEvents.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    sectionHeader("PASSATI", icon: "clock.arrow.circlepath")
                                        .padding(.top, (todayEvents.isEmpty && upcomingEvents.isEmpty) ? 0 : 10)
                                    ForEach(pastEvents) { event in
                                        eventRow(event, isPast: true)
                                    }
                                }
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 30) // spazio per la tab bar
                    }
                    .refreshable {
                        await withCheckedContinuation { continuation in
                            viewModel.fetchEvents(serverURL: server.httpURL) {
                                continuation.resume()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Eventi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Barra ricerca stile Live Timing
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                    TextField("", text: $searchText, prompt: Text("CERCA EVENTO").foregroundColor(.black))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .disableAutocorrection(true)
                }
                .environment(\.colorScheme, .light)
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
            
            if authState.currentUser?.role.canManageUsers == true {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        activeSheet = .new
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.kartAccent)
                    }
                }
            }
        }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .new:
                // Evento creato → ricarica la lista eventi
                EventiFormView(
                    server: server,
                    authState: authState,
                    viewModel: viewModel,
                    editingEvent: nil,
                    onSaved: { viewModel.fetchEvents(serverURL: server.httpURL) }
                )
            }
        }
        .fullScreenCover(item: $selectedEventToOpen) { event in
            // Vista dedicata all'evento — non chiudibile con swipe verso il basso
            EventRootView(server: server, event: event)
                .environmentObject(authState)
                .onDisappear {
                    // Riaggiorna iscrizioni e lista al ritorno
                    if let token = authState.currentToken {
                        viewModel.fetchUserRegistrations(serverURL: server.httpURL, token: token)
                    }
                    viewModel.fetchEvents(serverURL: server.httpURL)
                }
        }
        .onChange(of: appEnv.pendingEventIdToOpen) {
            if let pendingId = appEnv.pendingEventIdToOpen {
                if let event = viewModel.events.first(where: { $0.id == pendingId }) {
                    selectedEventToOpen = event
                    appEnv.pendingEventIdToOpen = nil
                } else if viewModel.events.isEmpty {
                    // Se gli eventi non sono ancora caricati, aspettiamo che lo siano
                    viewModel.fetchEvents(serverURL: server.httpURL)
                }
            }
        }
        .onChange(of: viewModel.events.count) {
            if let pendingId = appEnv.pendingEventIdToOpen, let event = viewModel.events.first(where: { $0.id == pendingId }) {
                selectedEventToOpen = event
                appEnv.pendingEventIdToOpen = nil
            }
        }
        .onAppear {
            if viewModel.events.isEmpty {
                viewModel.fetchEvents(serverURL: server.httpURL)
            }
            if let token = authState.currentToken {
                viewModel.fetchUserRegistrations(serverURL: server.httpURL, token: token)
            }
            
            // Se c'è un evento in sospeso e gli eventi sono già caricati, aprilo
            if let pendingId = appEnv.pendingEventIdToOpen, let event = viewModel.events.first(where: { $0.id == pendingId }) {
                selectedEventToOpen = event
                appEnv.pendingEventIdToOpen = nil
            }
        }
        .sheet(item: $eventForClassification) { event in
            ClassificationSheet(event: event, viewModel: analisiViewModel, server: server)
                .environmentObject(authState)
        }
    }
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(.kartAccent)
            Text(title)
                .foregroundColor(.kartAccent)
            Spacer()
        }
        .font(.system(size: 13, weight: .bold, design: .monospaced))
        .padding(.horizontal, 16)
    }
    
    // ── Event Row ─────────────────────────────────────────────────────────────
    private func eventRow(_ event: RaceEvent, isPast: Bool) -> some View {
        let isExpanded = expandedEventId == event.id
        
        return VStack(spacing: 0) {
            // Header: sempre visibile
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .foregroundColor(.kartAccent)
                            Text(event.formattedDate)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.kartAccent)
                            Text(event.location)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.kartDim)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.kartDim)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.kartPanel)
            
            // Corpo espanso
            if isExpanded {
                Divider().background(Color.white.opacity(0.1))

                VStack(spacing: 12) {
                    // Informazioni rapide: tipo gara e prezzo
                    HStack {
                        Text(event.isTeamEvent ? "GARA A SQUADRE" : "GARA INDIVIDUALE")
                            .font(.caption.bold())
                            .foregroundColor(event.isTeamEvent ? .yellow : .blue)
                        Spacer()
                        if let cost = event.registrationCost {
                            let priceLabel = event.isTeamEvent ? "Squadra" : "Prezzo"
                            detailText(label: priceLabel, value: "€ \(String(format: "%.2f", cost))")
                        }
                    }

                    // Badge stato iscrizione (solo utenti non admin)
                    let reg = viewModel.userRegistrations[event.id]
                    let isAdmin = authState.currentUser?.role.canManageUsers == true
                    if !isAdmin, let regStatus = reg?.status {
                        let (badgeLabel, badgeColor): (String, Color) = {
                            switch regStatus {
                            case "confirmed":       return ("✓ Iscrizione Confermata", .green)
                            case "waitlist":        return ("⏳ In Lista d'Attesa", .purple)
                            case "pending_payment": return ("⚠ In Attesa Pagamento", .yellow)
                            default:                return ("Iscritto", .gray)
                            }
                        }()
                        Text(badgeLabel)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(badgeColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Se passato, mostra Risultati, altrimenti Apri Evento
                    if isPast {
                        Button {
                            analisiViewModel.fetchClassification(serverURL: server.httpURL, eventId: event.id, token: authState.currentToken)
                            eventForClassification = event
                        } label: {
                            HStack(spacing: 6) {
                                Text("Risultati")
                                    .font(.system(size: 13, weight: .bold))
                                Image(systemName: "list.number")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.kartAccent)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        }
                    } else {
                        Button {
                            selectedEventToOpen = event
                        } label: {
                            HStack(spacing: 6) {
                                Text("Apri Evento")
                                    .font(.system(size: 13, weight: .bold))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.kartAccent)
                            .foregroundColor(.black)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.kartPanel.opacity(0.95))
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                if isExpanded {
                    expandedEventId = nil
                } else {
                    expandedEventId = event.id
                }
            }
        }
    }
    
    private func detailText(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .foregroundColor(.kartDim)
            Text(value)
                .foregroundColor(.white)
        }
        .font(.system(size: 11, weight: .medium))
    }
    
    // ── Header Bar (Stile Live Timing) ─────────────────────────────────────────
    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Eventi in programma")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            Spacer()
            Text("\(filteredEvents.count) trovati")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.kartDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kartPanel)
    }
}
