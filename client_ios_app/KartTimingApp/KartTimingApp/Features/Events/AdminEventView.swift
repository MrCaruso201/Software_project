import SwiftUI

/// Vista dedicata all'evento per utenti Admin.
/// NavigationStack + TabView con 5 tab: Info, Iscrizioni, Liberatorie, Modifica e Gestione.
struct AdminEventView: View {
    let server: DiscoveredServer
    let event: RaceEvent
    @ObservedObject var viewModel: EventsViewModel

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    // Stato locale dell'evento (aggiornato da toggleStatus)
    @State private var localEvent: RaceEvent
    @State private var showUploadResults = false
    @State private var selectedTab = 0
    @State private var showAddRegistrationSheet = false

    // Refresh del form dopo salvataggio
    @State private var editFormId = UUID()

    init(server: DiscoveredServer, event: RaceEvent, viewModel: EventsViewModel) {
        self.server = server
        self.event = event
        self.viewModel = viewModel
        _localEvent = State(initialValue: event)
    }

    private var isStarted: Bool { localEvent.status == "started" }
    private var isFinished: Bool { localEvent.status == "finished" }
    private var isAdmin: Bool { authState.currentUser?.role == .admin }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                // ── Tab 1: Info ───────────────────────────────────────────
                EventDetailContentView(
                    server: server,
                    event: $localEvent,
                    viewModel: viewModel
                )
                .tabItem { Label("Info", systemImage: "info.circle.fill") }
                .tag(0)

                // ── Tab 2: Iscrizioni ─────────────────────────────────────
                AdminEventRegistrationsView(
                    server: server,
                    viewModel: viewModel,
                    event: localEvent,
                    showAsSheet: false
                )
                .environmentObject(authState)
                .tabItem { Label("Iscrizioni", systemImage: "person.3.fill") }
                .tag(1)

                // ── Tab 3: Liberatorie ────────────────────────────────────
                AdminReleaseFormSheetView(server: server, viewModel: viewModel, event: localEvent)
                    .environmentObject(authState)
                    .tabItem { Label("Liberatorie", systemImage: "doc.text.fill") }
                    .tag(2)

                // ── Tab 4: Gestione ───────────────────────────────────────
                AdminManageEventView(
                    server: server,
                    localEvent: $localEvent,
                    isAdmin: isAdmin,
                    showUploadResults: $showUploadResults
                )
                .environmentObject(authState)
                .tabItem { Label("Gestione", systemImage: "gearshape.2.fill") }
                .tag(3)

                // ── Tab 5: Modifica ───────────────────────────────────────
                EventFormView(
                    server: server,
                    authState: authState,
                    viewModel: viewModel,
                    editingEvent: localEvent,
                    onSaved: {
                        // Ricarica la lista e aggiorna localEvent con i dati aggiornati dal server
                        viewModel.fetchEvents(serverURL: server.httpURL) {
                            if let updated = viewModel.events.first(where: { $0.id == localEvent.id }) {
                                localEvent = updated
                                // Forza il re-render del form con i dati aggiornati
                                editFormId = UUID()
                            }
                        }
                    },
                    suppressDismissOnSave: true
                )
                .id(editFormId)
                .tabItem { Label("Modifica", systemImage: "pencil.circle.fill") }
                .tag(4)
            }
            .tint(.kartAccent)
            .navigationTitle(localEvent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // ── Chiudi ────────────────────────────────────────────────
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                        .font(.system(size: 14, weight: .semibold))
                }

                // ── Indicatore stato gara ─────────────────────────────────
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        if isStarted {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                        }
                        Text(isStarted ? "LIVE" : isFinished ? "TERMINATA" : "PROGRAMMATA")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(isStarted ? .red : .gray)
                    }
                }

                // ── Aggiungi Iscrizione ───────────────────────────────────
                if selectedTab == 1 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showAddRegistrationSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.kartAccent)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showUploadResults) {
            UploadResultsView(server: server, event: localEvent)
                .environmentObject(authState)
        }
        .sheet(isPresented: $showAddRegistrationSheet, onDismiss: {
            NotificationCenter.default.post(name: NSNotification.Name("RefreshRegistrations"), object: nil)
        }) {
            AdminAddRegistrationSheetView(
                server: server,
                viewModel: viewModel,
                event: localEvent,
                isTeamEvent: localEvent.isTeamEvent
            )
            .environmentObject(authState)
        }
    }
}
