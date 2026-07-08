import SwiftUI

struct EventiView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = EventiViewModel()
    
    @State private var searchText = ""
    @State private var expandedEventId: Int? = nil
    
    // Gestione Form e Modifica
    enum ActiveSheet: Identifiable {
        case new
        case edit(RaceEvent)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let e): return "edit-\(e.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet? = nil
    
    var filteredEvents: [RaceEvent] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return viewModel.events }
        return viewModel.events.filter { event in
            event.title.lowercased().contains(q) ||
            event.location.lowercased().contains(q) ||
            event.formattedDate.lowercased().contains(q)
        }
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
                        LazyVStack(spacing: 12) {
                            ForEach(filteredEvents) { event in
                                eventRow(event)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 30) // spazio per la tab bar
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
                EventiFormView(server: server, authState: authState, viewModel: viewModel, editingEvent: nil)
            case .edit(let event):
                EventiFormView(server: server, authState: authState, viewModel: viewModel, editingEvent: event)
            }
        }
        .onAppear {
            if viewModel.events.isEmpty {
                viewModel.fetchEvents(serverURL: server.httpURL)
            }
        }
    }
    
    // ── Event Row ─────────────────────────────────────────────────────────────
    private func eventRow(_ event: RaceEvent) -> some View {
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
                    // Dettagli Evento
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if let part = event.maxParticipants {
                                detailText(label: "Partecipanti", value: "Max \(part)")
                            } else {
                                detailText(label: "Partecipanti", value: "N/D")
                            }
                            if let grp = event.maxGroups {
                                detailText(label: "Gruppi", value: "Max \(grp)")
                            } else {
                                detailText(label: "Gruppi", value: "N/D")
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 4) {
                            if let cost = event.registrationCost {
                                detailText(label: "Prezzo", value: "€ \(String(format: "%.2f", cost))")
                            } else {
                                detailText(label: "Prezzo", value: "N/D")
                            }
                            if let weight = event.weightLimit {
                                detailText(label: "Peso", value: "Min \(String(format: "%.1f", weight))kg")
                            } else {
                                detailText(label: "Peso", value: "N/D")
                            }
                        }
                    }
                    .padding(.bottom, 4)
                    
                    // Pulsanti
                    HStack(spacing: 12) {
                        Button {
                            // Azione Maggiori Info
                        } label: {
                            Text("Maggiori info")
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.1))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        
                        if authState.currentUser?.role.canManageUsers == true {
                            // Admin: pulsante Modifica
                            Button {
                                activeSheet = .edit(event)
                            } label: {
                                Text("Modifica")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.kartAccent)
                                    .foregroundColor(.black)
                                    .cornerRadius(8)
                            }
                        } else {
                            // Utente normale: pulsante Iscriviti
                            Button {
                                // Azione Iscriviti
                            } label: {
                                Text("Iscriviti")
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color.kartAccent)
                                    .foregroundColor(.black)
                                    .cornerRadius(8)
                            }
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
