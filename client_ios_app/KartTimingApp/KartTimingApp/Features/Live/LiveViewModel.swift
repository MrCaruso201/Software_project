import Foundation
import Combine

@MainActor
class LiveViewModel: ObservableObject {

    // MARK: - Published State

    @Published var kartAssignments: [LiveKartAssignment] = []
    @Published var penalties: [RacePenalty] = [] {
        didSet {
            penaltiesByKart = Dictionary(grouping: penalties, by: \.kartNumber)
            penaltyTotals = penaltiesByKart.mapValues { $0.reduce(0) { $0 + ($1.seconds ?? 0) } }
        }
    }
    @Published var penaltyTypes: [PenaltyType] = []
    @Published var messages: [RaceMessage] = []
    @Published var driverSwap = DriverSwapSelection()
    @Published var myKart: MyKartResponse = MyKartResponse() {
        didSet { driverSwap.update(with: myKart) }
    }
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
    private var refreshTask: Task<Void, Never>?
    private var refreshPending = false
    private var pendingScopes: Set<String> = []
    private var isDirector = false
    private var ownMutationRequests: [String] = []
    private var pitVersion = 0
    private var generation = UUID()
    private var penaltyTypesFetchedAt: Date?
    
    private var lastFetchedData: [String: Data] = [:]

    private var timingManager: KartTimingManager?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init / Setup

    func configure(serverURL: URL?, token: String?, eventId: Int, isDirector: Bool = false, timingManager: KartTimingManager? = nil) {
        if self.eventId != eventId || self.token != token || self.serverURL != serverURL {
            driverSwap = DriverSwapSelection()
        }
        stopPolling()
        lastFetchedData.removeAll()
        penaltyTypesFetchedAt = nil
        self.serverURL = serverURL
        self.token = token
        self.eventId = eventId
        self.isDirector = isDirector
        registeredTeams = []
        registeredIndividuals = []
        ownMutationRequests = []
        self.timingManager = timingManager
        
        timingManager?.$lastEventUpdate
            .dropFirst()
            .compactMap { $0 }
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.fetchAll() }
            }
            .store(in: &cancellables)

        timingManager?.pitUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self, update.eventId == self.eventId else { return }
                if let requestId = update.requestId, self.ownMutationRequests.contains(requestId) { return }
                Task { await self.refresh(pitOnly: true) }
            }
            .store(in: &cancellables)
        timingManager?.flagUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                guard let self, update.eventId == self.eventId else { return }
                if let id = update.requestId, self.ownMutationRequests.contains(id) { return }
                var scopes: Set<String> = [update.change]
                if update.kartsChanged { scopes.insert("pit") }
                Task { await self.refresh(scopes: scopes) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Legacy Polling (Removed)

    func startPolling() {
        Task { await fetchAll() }
    }

    func stopPolling() {
        cancellables.removeAll()
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        refreshPending = false
        pendingScopes = []
    }


    // MARK: - Fetch All (director)

    private func fetchRawData(path: String, enabled: Bool = true) async -> Data? {
        guard enabled else { return nil }
        guard let url = endpoint(path), let token = token else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await NetworkService.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    func fetchPenaltyTypesOnly() async {
        if let data = await fetchRawData(path: "/live/penalty-types") {
            if let types = try? JSONDecoder().decode([PenaltyType].self, from: data) {
                self.penaltyTypes = types
            }
        }
    }

    func fetchAll() async { await refresh(pitOnly: false) }

    private func refresh(pitOnly: Bool) async {
        await refresh(scopes: pitOnly ? ["pit"] : ["full"])
    }

    private func refresh(scopes: Set<String>) async {
        pendingScopes.formUnion(scopes)
        if let refreshTask {
            refreshPending = true
            await refreshTask.value
            return
        }
        let currentGeneration = generation
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.refreshPending = false
                let scopes = self.pendingScopes
                self.pendingScopes = []
                await self.fetchSnapshot(generation: currentGeneration, scopes: scopes)
            } while self.refreshPending && !Task.isCancelled && self.generation == currentGeneration
        }
        refreshTask = task
        await task.value
        if generation == currentGeneration { refreshTask = nil }
    }

    private func fetchPenaltyTypesIfNeeded(enabled: Bool) async -> Data? {
        guard enabled else { return nil }
        if let fetched = penaltyTypesFetchedAt, Date().timeIntervalSince(fetched) < 300 { return nil }
        return await fetchRawData(path: "/live/penalty-types")
    }

    private func fetchSnapshot(generation: UUID, scopes: Set<String>) async {
        let version = pitVersion
        let director = isDirector
        let full = scopes.contains("full")
        let karts = full || scopes.contains("pit") || scopes.contains("penalties")
        let penalties = full || scopes.contains("penalties")
        let messages = full || scopes.contains("messages")
        async let eventData = fetchRawData(path: "/events/\(eventId)", enabled: full)
        async let kartsData = fetchRawData(path: "/live/\(eventId)/karts", enabled: karts)
        async let typesData = fetchPenaltyTypesIfNeeded(enabled: full && director)
        async let penaltiesData = fetchRawData(path: "/live/\(eventId)/penalties", enabled: penalties)
        async let messagesData = fetchRawData(path: "/live/\(eventId)/messages", enabled: messages)
        async let teamsData = fetchRawData(path: "/events/\(eventId)/registrations/teams", enabled: full && director)
        async let individualsData = fetchRawData(path: "/events/\(eventId)/registrations", enabled: full && director)
        async let resultsData = fetchRawData(path: "/events/\(eventId)/results", enabled: full)
        async let myKartData = fetchRawData(path: "/live/\(eventId)/my-kart", enabled: !director)
        
        let (eventD, kartsD, typesD, penaltiesD, messagesD, teamsD, individualsD, resultsD, myKartD) = await (
            eventData, kartsData, typesData, penaltiesData, messagesData, teamsData, individualsData, resultsData, myKartData
        )
        
        guard generation == self.generation, !Task.isCancelled else { return }
        
        let received: [String: Data?] = [
            "event": eventD,
            "karts": kartsD,
            "mykart": myKartD,
            "types": typesD,
            "penalties": penaltiesD,
            "messages": messagesD,
            "teams": teamsD,
            "individuals": individualsD,
            "results": resultsD
        ]
        let changed = received.compactMapValues { $0 }.filter { lastFetchedData[$0.key] != $0.value }
        let snapshot = await LiveSnapshot.decode(changed)
        guard generation == self.generation, !Task.isCancelled else { return }

        // Publish together after decoding, without suspending between assignments.
        if let typesD, typesD == lastFetchedData["types"] { penaltyTypesFetchedAt = Date() }
        if let value = snapshot.event {
            lastFetchedData["event"] = eventD
            self.currentSessionName = value.sessionName
        }
        if version != pitVersion { refreshPending = true; pendingScopes.insert("pit") }
        if let value = snapshot.karts, version == pitVersion {
            lastFetchedData["karts"] = kartsD
            self.kartAssignments = value
        }
        if let value = snapshot.myKart, version == pitVersion {
            lastFetchedData["mykart"] = myKartD
            self.myKart = value
        }
        if let value = snapshot.types {
            lastFetchedData["types"] = typesD
            self.penaltyTypes = value
            penaltyTypesFetchedAt = Date()
        }
        if let value = snapshot.penalties {
            lastFetchedData["penalties"] = penaltiesD
            self.penalties = value
        }
        if let value = snapshot.messages {
            lastFetchedData["messages"] = messagesD
            self.messages = value
            syncRaceTimesFromMessages(value)
        }
        if let value = snapshot.teams {
            lastFetchedData["teams"] = teamsD
            self.registeredTeams = value
        }
        if let value = snapshot.individuals {
            lastFetchedData["individuals"] = individualsD
            self.registeredIndividuals = value
        }
        if let value = snapshot.results {
            lastFetchedData["results"] = resultsD
            self.eventResults = value
        }
    }
    
    // Alias temporanei per funzioni richiamate singolarmente da altri file
    func fetchEvent() async { await fetchAll() }
    func fetchMyKart() async { await fetchAll() }
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
              let token else { throw URLError(.badURL) }
        let currentGeneration = generation
        let requestId = UUID().uuidString
        ownMutationRequests.append(requestId)
        if ownMutationRequests.count > 128 { ownMutationRequests.removeFirst() }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(requestId, forHTTPHeaderField: "X-Request-ID")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["is_in_pit": isInPit])
        do {
            let (data, response) = try await NetworkService.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore aggiornamento pit"
                throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            let assignment = try await BackgroundJSON.decode(LiveKartAssignment.self, from: data)
            guard generation == currentGeneration else { return }
            pitVersion += 1
            if let index = kartAssignments.firstIndex(where: { $0.kartNumber == kartNumber }) {
                kartAssignments[index] = assignment
            } else {
                kartAssignments.append(assignment)
            }
            lastFetchedData["karts"] = nil
        } catch {
            // The write may have reached the server even if its response was lost.
            if generation == currentGeneration { await refresh(pitOnly: true) }
            throw error
        }
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
        try await performFlagMutation(req, scopes: ["penalties"])
    }

    func deletePenalty(id: Int) async throws {
        guard let url = endpoint("/live/\(eventId)/penalties/\(id)"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        try await performFlagMutation(req, scopes: ["penalties"])
    }

    func updatePenaltyType(id: Int, defaultSeconds: Int?, warningThreshold: Int?) async throws -> PenaltyType {
        guard let url = endpoint("/live/penalty-types/\(id)"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [:]
        if let ds = defaultSeconds { body["default_seconds"] = ds }
        if let wt = warningThreshold { body["warning_threshold"] = wt }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode >= 200 && http.statusCode < 300 else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore aggiornamento tipo penalità"
            throw NSError(domain: "", code: (resp as? HTTPURLResponse)?.statusCode ?? 500, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        
        let updated = try JSONDecoder().decode(PenaltyType.self, from: data)
        if let index = penaltyTypes.firstIndex(where: { $0.id == updated.id }) {
            penaltyTypes[index] = updated
        }
        return updated
    }

    private static func messageScopes(type: String, text: String) -> Set<String> {
        let textLower = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let changesTimers = ["red_flag", "green_flag", "checkered_flag"].contains(type)
            || (type == "custom" && (textLower == "gara iniziata" || textLower == "turno iniziato"))
        return changesTimers ? ["messages", "pit"] : ["messages"]
    }

    private func performFlagMutation(_ request: URLRequest, scopes: Set<String>) async throws {
        let currentGeneration = generation
        let id = UUID().uuidString
        ownMutationRequests.append(id)
        if ownMutationRequests.count > 128 { ownMutationRequests.removeFirst() }
        var request = request
        request.setValue(id, forHTTPHeaderField: "X-Request-ID")
        do {
            let (data, response) = try await NetworkService.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore aggiornamento live"
                throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
        } catch {
            if generation == currentGeneration { await refresh(scopes: scopes) }
            throw error
        }
        // Fetch authoritative state, including penalties automatically created by the server.
        if generation == currentGeneration { await refresh(scopes: scopes) }
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
            case "custom" where msg.text.lowercased() == "gara iniziata" || msg.text.lowercased() == "turno iniziato":
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
        try await performFlagMutation(req, scopes: Self.messageScopes(type: type.rawValue, text: text))
    }

    func deleteMessage(id: Int) async throws {
        guard let url = endpoint("/live/\(eventId)/messages/\(id)"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        try await performFlagMutation(req, scopes: ["messages"])
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
    private(set) var penaltiesByKart: [Int: [RacePenalty]] = [:]
    private var penaltyTotals: [Int: Int] = [:]

    func totalPenaltySeconds(for kartNumber: Int) -> Int {
        penaltyTotals[kartNumber] ?? 0
    }
}

/// Transferable snapshot prepared off the UI executor.
nonisolated private struct LiveSnapshot: Sendable {
    var event: RaceEvent?
    var karts: [LiveKartAssignment]?
    var myKart: MyKartResponse?
    var types: [PenaltyType]?
    var penalties: [RacePenalty]?
    var messages: [RaceMessage]?
    var teams: [TeamRegistrationResponse]?
    var individuals: [EventRegistrationWithUserResponse]?
    var results: [EventResult]?

    @concurrent
    static func decode(_ data: [String: Data]) async -> LiveSnapshot {
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
            guard let bytes = data[key] else { return nil }
            return try? decoder.decode(type, from: bytes)
        }
        return LiveSnapshot(
            event: decode(RaceEvent.self, key: "event"),
            karts: decode([LiveKartAssignment].self, key: "karts"),
            myKart: decode(MyKartResponse.self, key: "mykart"),
            types: decode([PenaltyType].self, key: "types"),
            penalties: decode([RacePenalty].self, key: "penalties"),
            messages: decode([RaceMessage].self, key: "messages"),
            teams: decode([TeamRegistrationResponse].self, key: "teams"),
            individuals: decode([EventRegistrationWithUserResponse].self, key: "individuals"),
            results: decode([EventResult].self, key: "results")
        )
    }
}
