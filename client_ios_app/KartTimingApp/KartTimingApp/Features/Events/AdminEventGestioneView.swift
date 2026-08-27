import SwiftUI

/// Tab "Gestione" nella AdminEventView.
/// Contiene i controlli di stato gara (Avvia, Termina, Ripristina, Carica Risultati).
/// In futuro potranno essere aggiunti altri controlli amministrativi.
struct AdminEventGestioneView: View {
    let server: DiscoveredServer
    @Binding var localEvent: RaceEvent
    let isAdmin: Bool
    @Binding var showUploadResults: Bool

    @EnvironmentObject var authState: AuthState

    @State private var isUpdatingStatus = false
    @State private var statusError: String? = nil
    @State private var showStatusConfirm = false
    @State private var pendingStatus: String? = nil
    @State private var showLive = false

    private var isStarted: Bool { localEvent.status == "started" }
    private var isFinished: Bool { localEvent.status == "finished" }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    // MARK: - Header sezione
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.kartAccent)
                            Text("GESTIONE EVENTO")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .foregroundColor(.kartAccent)
                            Spacer()
                            // Badge stato
                            Text(isStarted ? "LIVE" : isFinished ? "TERMINATA" : "PROGRAMMATA")
                                .font(.system(size: 10, weight: .black, design: .monospaced))
                                .foregroundColor(isStarted ? .black : isFinished ? .kartDim : .kartAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isStarted ? Color.kartAccent : Color.kartPanel)
                                .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // MARK: - Controlli stato gara
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.kartAccent)
                            Text("STATO GARA")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartAccent)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.kartAccent.opacity(0.08))

                        VStack(spacing: 12) {
                            if !isFinished {
                                // Avvia Evento / Termina Evento
                                Button(action: {
                                    pendingStatus = isStarted ? "finished" : "started"
                                    showStatusConfirm = true
                                }) {
                                    HStack(spacing: 10) {
                                        if isUpdatingStatus {
                                            ProgressView()
                                                .tint(isStarted ? .red : .black)
                                                .scaleEffect(0.85)
                                        } else {
                                            Image(systemName: isStarted ? "stop.circle.fill" : "play.circle.fill")
                                                .font(.system(size: 17, weight: .semibold))
                                            Text(isStarted ? "Termina Evento" : "Avvia Evento")
                                                .font(.system(size: 15, weight: .bold))
                                        }
                                        Spacer()
                                    }
                                    .foregroundColor(isStarted ? .red : .black)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        isStarted
                                            ? Color.red.opacity(0.15)
                                            : Color.kartAccent
                                    )
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(isStarted ? Color.red.opacity(0.4) : Color.clear, lineWidth: 1)
                                    )
                                    .shadow(
                                        color: isStarted ? Color.red.opacity(0.2) : Color.kartAccent.opacity(0.3),
                                        radius: 8, x: 0, y: 4
                                    )
                                }
                                .disabled(isUpdatingStatus)

                                // Entra in Live
                                if isStarted {
                                    Button(action: { showLive = true }) {
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
                            }

                            if isFinished && isAdmin {
                                // Carica Risultati
                                Button(action: { showUploadResults = true }) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.up.doc.fill")
                                            .font(.system(size: 17, weight: .semibold))
                                        Text("Carica Risultati")
                                            .font(.system(size: 15, weight: .bold))
                                        Spacer()
                                    }
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.kartAccent)
                                    .cornerRadius(14)
                                    .shadow(color: Color.kartAccent.opacity(0.3), radius: 8, x: 0, y: 4)
                                }

                                // Ripristina a Programmata
                                Button(action: {
                                    pendingStatus = "scheduled"
                                    showStatusConfirm = true
                                }) {
                                    HStack(spacing: 10) {
                                        if isUpdatingStatus {
                                            ProgressView().tint(.orange).scaleEffect(0.85)
                                        } else {
                                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                                .font(.system(size: 17, weight: .semibold))
                                            Text("Ripristina a 'Programmata'")
                                                .font(.system(size: 15, weight: .bold))
                                        }
                                        Spacer()
                                    }
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.orange.opacity(0.12))
                                    .cornerRadius(14)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                                    )
                                }
                                .disabled(isUpdatingStatus)
                            }

                            if let err = statusError {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                                    Text(err).font(.system(size: 12)).foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                    }
                    .background(Color.kartPanel)
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
                    .padding(.horizontal, 16)

                    Spacer(minLength: 40)
                }
                .padding(.top, 16)
            }
        }
        .confirmationDialog(confirmTitle, isPresented: $showStatusConfirm, titleVisibility: .visible) {
            Button(confirmButtonLabel, role: pendingStatus == "finished" ? .destructive : nil) {
                guard let s = pendingStatus else { return }
                Task { await toggleEventStatus(to: s) }
            }
            Button("Annulla", role: .cancel) { }
        }
        .fullScreenCover(isPresented: $showLive) {
            LiveRootView(server: server, event: localEvent)
                .environmentObject(authState)
        }
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
            let (data, resp) = try await NetworkService.shared.data(for: req)
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
        case "started":   return "Avviare l'evento?"
        case "finished":  return "Terminare l'evento?"
        case "scheduled": return "Ripristinare lo stato a 'Programmata'?"
        default:          return "Conferma"
        }
    }

    private var confirmButtonLabel: String {
        switch pendingStatus {
        case "started":   return "Avvia Evento"
        case "finished":  return "Termina Evento"
        case "scheduled": return "Ripristina"
        default:          return "Conferma"
        }
    }
}
