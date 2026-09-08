import Foundation
import Combine

@MainActor
class LiveViewModel: ObservableObject {

    // MARK: - Published State

    @Published var kartAssignments: [LiveKartAssignment] = []
    @Published var penalties: [RacePenalty] = []
    @Published var penaltyTypes: [PenaltyType] = []
    @Published var messages: [RaceMessage] = []
    @Published var myKart: MyKartResponse = MyKartResponse()
    @Published var registeredTeams: [TeamRegistrationResponse] = []
    @Published var registeredIndividuals: [EventRegistrationWithUserResponse] = []
    @Published var currentSessionName: String? = nil
    @Published var eventResults: [EventResult] = []

    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    @Published var raceStartTime: Date? = nil
    @Published var raceEndTime: Date? = nil

    // MARK: - Config

    private var serverURL: URL?
    private var token: String?
    private var eventId: Int = 0
    private var pollingTask: Task<Void, Never>?
    private let pollingInterval: TimeInterval = 5

    // MARK: - Init / Setup

    func configure(serverURL: URL?, token: String?, eventId: Int) {
        self.serverURL = serverURL
        self.token = token
        self.eventId = eventId
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchAll()
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Fetch All (director)

    func fetchAll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchEvent() }
            group.addTask { await self.fetchKartAssignments() }
            group.addTask { await self.fetchPenaltyTypes() }
            group.addTask { await self.fetchPenalties() }
            group.addTask { await self.fetchMessages() }
            group.addTask { await self.fetchRegisteredTeams() }
            group.addTask { await self.fetchRegisteredIndividuals() }
            group.addTask { await self.fetchResults() }
        }
    }

    // MARK: - Fetch Event
    
    func fetchEvent() async {
        guard let url = endpoint("/events/\(eventId)"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            let decoded = try JSONDecoder().decode(RaceEvent.self, from: data)
            DispatchQueue.main.async {
                self.currentSessionName = decoded.sessionName
            }
        } catch {
            print("Error fetching event details:", error)
        }
    }

    // MARK: - Fetch Results
    
    private func fetchResults() async {
        guard let url = endpoint("/events/\(eventId)/results"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            let decoded = try JSONDecoder().decode([EventResult].self, from: data)
            DispatchQueue.main.async { self.eventResults = decoded }
        } catch {
            print("Error fetching results:", error)
        }
    }

    // MARK: - Fetch My Kart (user)

    func fetchMyKart() async {
        guard let url = endpoint("/live/\(eventId)/my-kart"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            let decoded = try JSONDecoder().decode(MyKartResponse.self, from: data)
            self.myKart = decoded
        } catch {
            // Silenzioso: in caso di errore mostra dati vuoti
            self.myKart = MyKartResponse()
        }
    }

    func startPollingMyKart() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                await fetchEvent()
                await fetchMyKart()
                await fetchMessages()   // necessario per syncRaceTimesFromMessages → timer
                await fetchPenalties()
                await fetchResults()
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }

    // MARK: - Registered Teams
    
    private func fetchRegisteredTeams() async {
        guard let url = endpoint("/events/\(eventId)/registrations/teams"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            self.registeredTeams = try JSONDecoder().decode([TeamRegistrationResponse].self, from: data)
        } catch { }
    }

    private func fetchRegisteredIndividuals() async {
        guard let url = endpoint("/events/\(eventId)/registrations"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            self.registeredIndividuals = try JSONDecoder().decode([EventRegistrationWithUserResponse].self, from: data)
        } catch { }
    }

    // MARK: - Kart Assignments

    private func fetchKartAssignments() async {
        guard let url = endpoint("/live/\(eventId)/karts"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            self.kartAssignments = try JSONDecoder().decode([LiveKartAssignment].self, from: data)
        } catch { }
    }

    func assignKart(teamId: String, kartNumber: Int, teamName: String?) async throws {
        guard let url = endpoint("/live/\(eventId)/karts"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any?] = ["team_id": teamId, "kart_number": kartNumber, "team_name": teamName]
        req.httpBody = try JSONSerialization.data(withJSONObject: body.compactMapValues { $0 })
        let (data, resp) = try await NetworkService.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        await fetchAll()
    }

    func removeKart(kartNumber: Int) async throws {
        guard let url = endpoint("/live/\(eventId)/karts/\(kartNumber)"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await NetworkService.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        await fetchAll()
    }

    func updateRegistrationWeight(registrationId: Int, weight: Double) async throws {
        guard let url = endpoint("/events/\(eventId)/registrations/\(registrationId)"),
              let token = token else { throw URLError(.badURL) }
        
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = ["weight": weight]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        let (data, resp) = try await NetworkService.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore aggiornamento peso"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        await fetchAll()
    }

    // MARK: - Penalties

    private func fetchPenaltyTypes() async {
        guard let url = endpoint("/live/penalty-types"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            self.penaltyTypes = try JSONDecoder().decode([PenaltyType].self, from: data)
        } catch { }
    }

    private func fetchPenalties() async {
        guard let url = endpoint("/live/\(eventId)/penalties"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            self.penalties = try JSONDecoder().decode([RacePenalty].self, from: data)
        } catch { }
    }

    func addPenalty(kartNumber: Int, type: PenaltyType, seconds: Int?, note: String?) async throws {
        guard let url = endpoint("/live/\(eventId)/penalties"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["kart_number": kartNumber, "penalty_type": type.code]
        if let s = seconds { body["seconds"] = s }
        if let n = note, !n.isEmpty { body["note"] = n }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await NetworkService.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        await fetchAll()
    }

    func deletePenalty(id: Int) async throws {
        guard let url = endpoint("/live/\(eventId)/penalties/\(id)"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await NetworkService.shared.data(for: req)
        await fetchAll()
    }

    // MARK: - Messages

    private func fetchMessages() async {
        guard let url = endpoint("/live/\(eventId)/messages"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await NetworkService.shared.data(for: req)
            let decoded = try JSONDecoder().decode([RaceMessage].self, from: data)
            self.messages = decoded
            // Ricalcola raceStartTime e raceEndTime dai messaggi del server
            syncRaceTimesFromMessages(decoded)
        } catch { }
    }

    /// Ricava raceStartTime e raceEndTime dai messaggi broadcast in ordine cronologico.
    /// - "Gara Iniziata" (custom) → imposta raceStartTime, azzera raceEndTime
    /// - "checkered_flag" → imposta raceEndTime
    private func syncRaceTimesFromMessages(_ msgs: [RaceMessage]) {
        let broadcast = msgs
            .filter { $0.isBroadcast }
            .sorted {
                guard let d1 = $0.parsedDate, let d2 = $1.parsedDate else { return false }
                return d1 < d2
            }

        var newStart: Date? = nil
        var newEnd: Date? = nil

        for msg in broadcast {
            switch msg.messageType {
            case "custom" where msg.text.lowercased() == "gara iniziata":
                newStart = msg.parsedDate
                newEnd = nil   // reset: gara ripartita
            case "checkered_flag":
                newEnd = msg.parsedDate
            default:
                break
            }
        }

        // Aggiorna solo se i valori sono cambiati per evitare re-render inutili
        if raceStartTime != newStart { raceStartTime = newStart }
        if raceEndTime   != newEnd   { raceEndTime   = newEnd   }
    }

    func sendMessage(targetKart: Int?, type: MessagePreset, text: String) async throws {
        guard let url = endpoint("/live/\(eventId)/messages"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["message_type": type.rawValue, "text": text]
        if let k = targetKart { body["target_kart"] = k }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await NetworkService.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        await fetchAll()
    }

    func deleteMessage(id: Int) async throws {
        guard let url = endpoint("/live/\(eventId)/messages/\(id)"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await NetworkService.shared.data(for: req)
        await fetchAll()
    }

    // MARK: - Event Status

    func updateEventStatus(_ newStatus: String? = nil, sessionName: String? = nil) async throws {
        guard let url = endpoint("/events/\(eventId)/status"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var bodyParams: [String: Any] = [:]
        if let newStatus = newStatus {
            bodyParams["status"] = newStatus
        }
        if let sessionName = sessionName {
            bodyParams["session_name"] = sessionName
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyParams)
        let (data, resp) = try await NetworkService.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        // Force fetch to update locally
        await fetchEvent()
    }

    // MARK: - CSV Upload

    func uploadResultsCSV(fileURL: URL, resultType: String) async throws -> Int {
        guard let token = token else { throw URLError(.userAuthenticationRequired) }
        
        // Remove /api if present as we need the events endpoint
        guard let base = serverURL?.absoluteString.replacingOccurrences(of: "/api", with: "") else { throw URLError(.badURL) }
        let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let uploadURL = URL(string: "\(cleanBase)/events/\(eventId)/results/import_csv?result_type=\(resultType)") else { throw URLError(.badURL) }
        
        let didStart = fileURL.startAccessingSecurityScopedResource()
        defer { if didStart { fileURL.stopAccessingSecurityScopedResource() } }
        
        let csvData = try Data(contentsOf: fileURL)
        let boundary = "Boundary-\(UUID().uuidString)"
        
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        let filename = fileURL.lastPathComponent
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(csvData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let (data, response) = try await NetworkService.shared.data(for: request)
        
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 200 {
                struct ImportResp: Decodable { let imported: Int; let errors: [String] }
                if let resp = try? JSONDecoder().decode(ImportResp.self, from: data) {
                    await fetchResults()
                    return resp.imported
                }
                await fetchResults()
                return 0
            } else {
                let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore \(http.statusCode)"
                throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
        throw URLError(.badServerResponse)
    }

    func deleteResultsCSV(resultType: String) async throws {
        guard let token = token else { throw URLError(.userAuthenticationRequired) }
        guard let base = serverURL?.absoluteString.replacingOccurrences(of: "/api", with: "") else { throw URLError(.badURL) }
        let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard let deleteURL = URL(string: "\(cleanBase)/events/\(eventId)/results?result_type=\(resultType)") else { throw URLError(.badURL) }

        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkService.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 204 || http.statusCode == 200 {
                await fetchResults()
                return
            } else {
                let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore \(http.statusCode)"
                throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
        throw URLError(.badServerResponse)
    }

    // MARK: - Helpers

    private func endpoint(_ path: String) -> URL? {
        guard let base = serverURL?.absoluteString else { return nil }
        let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: cleanBase + path)
    }

    /// Restituisce le penalità raggruppate per numero kart
    var penaltiesByKart: [Int: [RacePenalty]] {
        Dictionary(grouping: penalties, by: \.kartNumber)
    }

    /// Penalità totali in secondi per un determinato kart
    func totalPenaltySeconds(for kartNumber: Int) -> Int {
        penalties
            .filter { $0.kartNumber == kartNumber }
            .reduce(0) { $0 + ($1.seconds ?? 0) }
    }
}
