import SwiftUI

/// Vista dedicata all'evento per utenti Admin.
/// NavigationStack + TabView con 3 tab: Info, Iscrizioni, Modifica.
struct AdminEventView: View {
    let server: DiscoveredServer
    let event: RaceEvent
    @ObservedObject var viewModel: EventiViewModel

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    // Stato locale dell'evento (aggiornato da toggleStatus)
    @State private var localEvent: RaceEvent
    @State private var showStatusConfirm = false
    @State private var pendingStatus: String? = nil
    @State private var isUpdatingStatus = false
    @State private var statusError: String? = nil

    // Refresh del form dopo salvataggio
    @State private var editFormId = UUID()

    init(server: DiscoveredServer, event: RaceEvent, viewModel: EventiViewModel) {
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
            TabView {
                // ── Tab 1: Info ───────────────────────────────────────────
                EventDetailContentView(
                    server: server,
                    event: $localEvent,
                    viewModel: viewModel
                )
                .tabItem { Label("Info", systemImage: "info.circle.fill") }

                // ── Tab 2: Iscrizioni ─────────────────────────────────────
                AdminEventRegistrationsView(
                    server: server,
                    viewModel: viewModel,
                    event: localEvent,
                    showAsSheet: false
                )
                .environmentObject(authState)
                .tabItem { Label("Iscrizioni", systemImage: "person.3.fill") }

                // ── Tab 3: Liberatorie ────────────────────────────────────
                AdminReleaseFormSheetView(server: server, viewModel: viewModel, event: localEvent)
                    .environmentObject(authState)
                    .tabItem { Label("Liberatorie", systemImage: "doc.text.fill") }

                // ── Tab 4: Modifica ───────────────────────────────────────
                EventiFormView(
                    server: server,
                    authState: authState,
                    viewModel: viewModel,
                    editingEvent: localEvent,
                    onSaved: {
                        // Aggiorna evento locale dopo il salvataggio
                        viewModel.fetchEvents(serverURL: server.httpURL)
                    }
                )
                .id(editFormId)
                .tabItem { Label("Modifica", systemImage: "pencil.circle.fill") }
            }
            .tint(.kartAccent)
            .navigationTitle(localEvent.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
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

                // ── Avvia / Termina / Ripristina ──────────────────────────
                ToolbarItem(placement: .navigationBarTrailing) {
                    Group {
                        if isFinished && isAdmin {
                            Button("Ripristina") {
                                pendingStatus = "scheduled"
                                showStatusConfirm = true
                            }
                            .foregroundColor(.orange)
                            .font(.system(size: 13, weight: .bold))
                        } else if !isFinished {
                            Button(isStarted ? "Termina" : "Avvia") {
                                pendingStatus = isStarted ? "finished" : "started"
                                showStatusConfirm = true
                            }
                            .foregroundColor(isStarted ? .red : .green)
                            .font(.system(size: 13, weight: .bold))
                            .disabled(isUpdatingStatus)
                        }
                    }
                }
            }
        }
        .confirmationDialog(confirmTitle, isPresented: $showStatusConfirm, titleVisibility: .visible) {
            Button(confirmButtonLabel, role: pendingStatus == "finished" ? .destructive : nil) {
                guard let s = pendingStatus else { return }
                Task { await toggleEventStatus(to: s) }
            }
            Button("Annulla", role: .cancel) { }
        }
        .alert("Errore", isPresented: .constant(statusError != nil), actions: {
            Button("OK") { statusError = nil }
        }, message: {
            Text(statusError ?? "")
        })
    }

    // MARK: - Status update

    @MainActor
    private func toggleEventStatus(to newStatus: String) async {
        guard let httpURL = server.httpURL,
              let token = authState.currentToken else { return }
        isUpdatingStatus = true
        statusError = nil
        do {
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
                    status: newStatus,
                    releaseFormText: localEvent.releaseFormText
                )
            }
        } catch {
            statusError = error.localizedDescription
        }
        isUpdatingStatus = false
    }

    // MARK: - Helpers

    private var confirmTitle: String {
        switch pendingStatus {
        case "started":   return "Avviare la gara?"
        case "finished":  return "Terminare la gara?"
        case "scheduled": return "Ripristinare lo stato a 'Programmata'?"
        default:          return "Conferma"
        }
    }

    private var confirmButtonLabel: String {
        switch pendingStatus {
        case "started":   return "Avvia Gara"
        case "finished":  return "Termina Gara"
        case "scheduled": return "Ripristina"
        default:          return "Conferma"
        }
    }
}
