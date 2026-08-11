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

    @Published var isLoading = false
    @Published var errorMessage: String? = nil

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
            group.addTask { await self.fetchKartAssignments() }
            group.addTask { await self.fetchPenaltyTypes() }
            group.addTask { await self.fetchPenalties() }
            group.addTask { await self.fetchMessages() }
            group.addTask { await self.fetchRegisteredTeams() }
        }
    }

    // MARK: - Fetch My Kart (user)

    func fetchMyKart() async {
        guard let url = endpoint("/live/\(eventId)/my-kart"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
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
                await fetchMyKart()
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
            let (data, _) = try await URLSession.shared.data(for: req)
            self.registeredTeams = try JSONDecoder().decode([TeamRegistrationResponse].self, from: data)
        } catch { }
    }

    // MARK: - Kart Assignments

    private func fetchKartAssignments() async {
        guard let url = endpoint("/live/\(eventId)/karts"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
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
            let (data, _) = try await URLSession.shared.data(for: req)
            self.penaltyTypes = try JSONDecoder().decode([PenaltyType].self, from: data)
        } catch { }
    }

    private func fetchPenalties() async {
        guard let url = endpoint("/live/\(eventId)/penalties"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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
        _ = try await URLSession.shared.data(for: req)
        await fetchAll()
    }

    // MARK: - Messages

    private func fetchMessages() async {
        guard let url = endpoint("/live/\(eventId)/messages"),
              let token = token else { return }
        do {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: req)
            self.messages = try JSONDecoder().decode([RaceMessage].self, from: data)
        } catch { }
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
        let (data, resp) = try await URLSession.shared.data(for: req)
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
        _ = try await URLSession.shared.data(for: req)
        await fetchAll()
    }

    // MARK: - Event Status

    func updateEventStatus(_ newStatus: String) async throws {
        guard let url = endpoint("/events/\(eventId)/status"),
              let token = token else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": newStatus])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"] ?? "Errore"
            throw NSError(domain: "", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }
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
