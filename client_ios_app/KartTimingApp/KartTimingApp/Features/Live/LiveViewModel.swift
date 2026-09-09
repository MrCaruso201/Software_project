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
    
    private var lastFetchedData: [String: Data] = [:]

    private var timingManager: KartTimingManager?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init / Setup

    func configure(serverURL: URL?, token: String?, eventId: Int, timingManager: KartTimingManager? = nil) {
        self.serverURL = serverURL
        self.token = token
        self.eventId = eventId
        self.timingManager = timingManager
        
        timingManager?.$lastEventUpdate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.fetchAll() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Legacy Polling (Removed)

    func startPolling() {
        Task { await fetchAll() }
    }

    func stopPolling() {
        cancellables.removeAll()
    }


    // MARK: - Fetch All (director)

    private func fetchRawData(path: String) async -> Data? {
        guard let url = endpoint(path), let token = token else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await NetworkService.shared.data(for: req)
            return data
        } catch {
            return nil
        }
    }

    func fetchAll() async {
        async let eventData = fetchRawData(path: "/events/\(eventId)")
        async let kartsData = fetchRawData(path: "/live/\(eventId)/karts")
        async let typesData = fetchRawData(path: "/live/penalty-types")
        async let penaltiesData = fetchRawData(path: "/live/\(eventId)/penalties")
        async let messagesData = fetchRawData(path: "/live/\(eventId)/messages")
        async let teamsData = fetchRawData(path: "/events/\(eventId)/registrations/teams")
        async let individualsData = fetchRawData(path: "/events/\(eventId)/registrations")
        async let resultsData = fetchRawData(path: "/events/\(eventId)/results")
        async let myKartData = fetchRawData(path: "/live/\(eventId)/my-kart")
        
        let (eventD, kartsD, typesD, penaltiesD, messagesD, teamsD, individualsD, resultsD, myKartD) = await (
            eventData, kartsData, typesData, penaltiesData, messagesData, teamsData, individualsData, resultsData, myKartData
        )
        
        // Assegnazione in blocco (batch update su main thread) per evitare scatti in UI
        let decoder = JSONDecoder()
        
        if let d = eventD, d != lastFetchedData["event"] {
            lastFetchedData["event"] = d
            if let dec = try? decoder.decode(RaceEvent.self, from: d) {
                self.currentSessionName = dec.sessionName
            }
        }
        
        if let d = kartsD, d != lastFetchedData["karts"] {
            lastFetchedData["karts"] = d
            if let dec = try? decoder.decode([LiveKartAssignment].self, from: d) {
                self.kartAssignments = dec
            }
        }
        
        if let d = myKartD, d != lastFetchedData["mykart"] {
            lastFetchedData["mykart"] = d
            if let dec = try? decoder.decode(MyKartResponse.self, from: d) {
                self.myKart = dec
            } else {
                self.myKart = MyKartResponse()
            }
        }
        
        if let d = typesD, d != lastFetchedData["types"] {
            lastFetchedData["types"] = d
            if let dec = try? decoder.decode([PenaltyType].self, from: d) {
                self.penaltyTypes = dec
            }
        }
        
        if let d = penaltiesD, d != lastFetchedData["penalties"] {
            lastFetchedData["penalties"] = d
            if let dec = try? decoder.decode([RacePenalty].self, from: d) {
                self.penalties = dec
            }
        }
        
        if let d = messagesD, d != lastFetchedData["messages"] {
            lastFetchedData["messages"] = d
            if let dec = try? decoder.decode([RaceMessage].self, from: d) {
                self.messages = dec
                syncRaceTimesFromMessages(dec)
            }
        }
        
        if let d = teamsD, d != lastFetchedData["teams"] {
            lastFetchedData["teams"] = d
            if let dec = try? decoder.decode([TeamRegistrationResponse].self, from: d) {
                self.registeredTeams = dec
            }
        }
        
        if let d = individualsD, d != lastFetchedData["individuals"] {
            lastFetchedData["individuals"] = d
            if let dec = try? decoder.decode([EventRegistrationWithUserResponse].self, from: d) {
                self.registeredIndividuals = dec
            }
        }
        
        if let d = resultsD, d != lastFetchedData["results"] {
            lastFetchedData["results"] = d
            if let dec = try? decoder.decode([EventResult].self, from: d) {
                self.eventResults = dec
            }
        }
    }
    
    // Alias temporanei per funzioni richiamate singolarmente da altri file
    func fetchEvent() async { await fetchAll() }
    func fetchMyKart() async { 
        if let d = await fetchRawData(path: "/live/\(eventId)/my-kart"), d != lastFetchedData["mykart"] {
            lastFetchedData["mykart"] = d
            if let dec = try? JSONDecoder().decode(MyKartResponse.self, from: d) {
                self.myKart = dec
            }
        }
    }
    private func fetchResults() async { await fetchAll() }
    private func fetchKartAssignments() async { await fetchAll() }

    func startPollingMyKart() {
        Task {
            await fetchAll()
        }
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

    func togglePitStatus(kartNumber: Int, isInPit: Bool) async throws {
        guard let url = endpoint("/live/\(eventId)/karts/\(kartNumber)/pit"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["is_in_pit": isInPit]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await NetworkService.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore aggiornamento pit"
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

    // Rimosso fetch individuale
    
    // MARK: - Penalties

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
