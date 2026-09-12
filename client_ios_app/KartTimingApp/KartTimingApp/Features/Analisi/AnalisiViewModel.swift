import Foundation
import Combine

// MARK: - AnalisiViewModel

class AnalisiViewModel: ObservableObject {

    // ── Dati grezzi ──────────────────────────────────────────────────────────
    @Published var myResults:      [EventResult]                 = [] { didSet { invalidateDerivedData() } }
    @Published var registrations:  [EventRegistrationResponse]   = [] { didSet { invalidateDerivedData() } }
    @Published var events:         [RaceEvent]                   = [] { didSet { invalidateDerivedData() } }
    @Published var allKartodromi:  [Kartodromo]                  = [] { didSet { invalidateDerivedData() } }
    @Published var kartodromiResults: [KartodromoResultResponse] = [] { didSet { invalidateDerivedData() } }
    
    @Published var isLoading:      Bool                          = true
    @Published var errorMessage:   String?                       = nil
    @Published var isReadOnly:     Bool                          = false
    @Published var targetUserId:   Int?                          = nil

    /// Classifiche complete di singoli eventi (fetched on-demand)
    @Published var classifications: [Int: [EventResult]]         = [:]
    
    /// Dati aggiuntivi per il PDF
    @Published var eventLapStats: [Int: [LapStatsResponse]]      = [:]
    @Published var eventPenalties: [Int: [RacePenalty]]          = [:]

    private var cachedPast: [(event: RaceEvent, reg: EventRegistrationResponse)]?
    private var cachedUpcoming: [(event: RaceEvent, reg: EventRegistrationResponse)]?
    private var cachedStats: [CircuitStat]?
    private var nextDateBoundary: Date?
    private var dateCache: [String: Date] = [:]

    private func invalidateDerivedData() {
        cachedPast = nil
        cachedUpcoming = nil
        cachedStats = nil
        nextDateBoundary = nil
    }

    private func validateDateBoundary() {
        if let boundary = nextDateBoundary, Date() >= boundary { invalidateDerivedData() }
        if nextDateBoundary == nil {
            let now = Date()
            nextDateBoundary = events.compactMap { parseDate(from: $0.eventDate) }.filter { $0 > now }.min()
                ?? .distantFuture
        }
    }

    // ── Computed helpers ─────────────────────────────────────────────────────

    private var confirmedRegistrations: [EventRegistrationResponse] {
        registrations.filter { $0.status == "confirmed" }
    }

    /// Gare passate a cui l'utente era iscritto (confirmed), ordinate per data desc
    var pastConfirmedEvents: [(event: RaceEvent, reg: EventRegistrationResponse)] {
        validateDateBoundary()
        if let cachedPast { return cachedPast }
        let now = Date()
        let eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let result = confirmedRegistrations.compactMap { reg -> (event: RaceEvent, reg: EventRegistrationResponse)? in
            guard let event = eventsByID[reg.eventId],
                  let date  = parseDate(from: event.eventDate) else { return nil }
            guard date < now || event.status == "finished" else { return nil }
            return (event, reg)
        }
        .sorted { a, b in
            (parseDate(from: a.event.eventDate) ?? .distantPast) >
            (parseDate(from: b.event.eventDate) ?? .distantPast)
        }
        cachedPast = result
        return result
    }

    /// Prossimi eventi confermati, ordinati per data asc
    var upcomingConfirmedEvents: [(event: RaceEvent, reg: EventRegistrationResponse)] {
        validateDateBoundary()
        if let cachedUpcoming { return cachedUpcoming }
        let now = Date()
        let eventsByID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let result = confirmedRegistrations.compactMap { reg -> (event: RaceEvent, reg: EventRegistrationResponse)? in
            guard let event = eventsByID[reg.eventId],
                  let date  = parseDate(from: event.eventDate) else { return nil }
            guard date > now && event.status != "finished" else { return nil }
            return (event, reg)
        }
        .sorted { a, b in
            (parseDate(from: a.event.eventDate) ?? .distantFuture) <
            (parseDate(from: b.event.eventDate) ?? .distantFuture)
        }
        cachedUpcoming = result
        return result
    }

    /// Statistiche per circuito, aggregate dai past events e dai risultati kartodromo
    var circuitStats: [CircuitStat] {
        validateDateBoundary()
        if let cachedStats { return cachedStats }
        var map: [String: CircuitStat] = [:]

        // 1. Inserisci gli eventi passati (escluse gare a squadre)
        for (event, reg) in pastConfirmedEvents {
            // Salta le gare a squadre: il tempo non è individuale
            guard reg.teamName == nil else { continue }

            let circuit = event.location.components(separatedBy: " - ").first ?? event.location
            let date    = parseDate(from: event.eventDate) ?? Date()
            let res     = myResults.first { $0.eventId == event.id }

            let entry = CircuitStat.Entry(
                id: event.id,
                eventTitle: event.title,
                eventDate: date,
                result: res
            )

            if map[circuit] == nil {
                let k = allKartodromi.first { $0.nome == circuit }
                let kResults = kartodromiResults.filter { $0.kartodromoId == k?.id }
                map[circuit] = CircuitStat(id: circuit, circuitName: circuit, kartodromoId: k?.id, kartodromoResults: kResults, entries: [])
            }
            map[circuit]!.entries.append(entry)
        }
        
        // 2. Aggiungi i kartodromi che non hanno eventi passati ma in cui ho un record
        for kr in kartodromiResults {
            if let k = allKartodromi.first(where: { $0.id == kr.kartodromoId }) {
                if map[k.nome] == nil {
                    let kResults = kartodromiResults.filter { $0.kartodromoId == k.id }
                    map[k.nome] = CircuitStat(id: k.nome, circuitName: k.nome, kartodromoId: k.id, kartodromoResults: kResults, entries: [])
                }
            }
        }

        let result = map.values.sorted { $0.racesCount > $1.racesCount }
        cachedStats = result
        return result
    }

    // ── Statistiche di riepilogo ──────────────────────────────────────────────

    var totalPastRaces: Int        { pastConfirmedEvents.count }
    var totalCircuitsVisited: Int  { Set(pastConfirmedEvents.map {
        $0.event.location.components(separatedBy: " - ").first ?? $0.event.location
    }).count }

    var bestOfficialPosition: Int? {
        pastConfirmedEvents
            .compactMap { result(for: $0.event.id)?.position }
            .min()
    }

    // ── Accesso risultati singolo evento ──────────────────────────────────────

    func result(for eventId: Int) -> EventResult? {
        myResults.first { $0.eventId == eventId }
    }

    // ── Network ──────────────────────────────────────────────────────────────

    func fetchAll(serverURL: URL?, token: String?) {
        fetchAll(serverURL: serverURL, token: token, forUserId: nil)
    }

    /// Carica i dati di un utente specifico (versione admin, usa endpoint /user/{id})
    func fetchAll(serverURL: URL?, token: String?, forUserId targetUserId: Int?) {
        guard let serverURL, let token else { isLoading = false; return }
        isLoading = true
        errorMessage = nil
        isReadOnly = (targetUserId != nil)
        self.targetUserId = targetUserId

        let group = DispatchGroup()

        if let uid = targetUserId {
            // ── Percorso Admin: endpoint /user/{id} ──────────────────────────
            group.enter()
            fetch(url: serverURL.appendingPathComponent("events/results/user/\(uid)"),
                  token: token,
                  type: [EventResult].self) { [weak self] result in
                if let res = result { self?.myResults = res }
                group.leave()
            }

            group.enter()
            fetch(url: serverURL.appendingPathComponent("events/registrations/user/\(uid)"),
                  token: token,
                  type: [EventRegistrationResponse].self) { [weak self] result in
                if let regs = result { self?.registrations = regs }
                group.leave()
            }

            group.enter()
            fetch(url: serverURL.appendingPathComponent("kartodromi/results/user/\(uid)"),
                  token: token,
                  type: [KartodromoResultResponse].self) { [weak self] result in
                if let kr = result { self?.kartodromiResults = kr }
                group.leave()
            }
        } else {
            // ── Percorso Utente: endpoint /me ─────────────────────────────────
            group.enter()
            fetch(url: serverURL.appendingPathComponent("events/registrations/me"),
                  token: token,
                  type: [EventRegistrationResponse].self) { [weak self] result in
                if let regs = result { self?.registrations = regs }
                group.leave()
            }

            group.enter()
            fetch(url: serverURL.appendingPathComponent("events/results/me"),
                  token: token,
                  type: [EventResult].self) { [weak self] result in
                if let res = result { self?.myResults = res }
                group.leave()
            }

            group.enter()
            fetch(url: serverURL.appendingPathComponent("kartodromi/results/me"),
                  token: token,
                  type: [KartodromoResultResponse].self) { [weak self] result in
                if let kr = result { self?.kartodromiResults = kr }
                group.leave()
            }
        }

        // Tutti i kartodromi e tutti gli eventi: sempre dagli endpoint pubblici
        group.enter()
        fetch(url: serverURL.appendingPathComponent("events/"),
              token: token,
              type: [RaceEvent].self) { [weak self] result in
            if let evs = result { self?.events = evs }
            group.leave()
        }

        group.enter()
        fetch(url: serverURL.appendingPathComponent("kartodromi/"),
              token: token,
              type: [Kartodromo].self) { [weak self] result in
            if let k = result { self?.allKartodromi = k }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.isLoading = false
        }
    }

    /// Carica la classifica completa di un evento (on-demand)
    func fetchClassification(serverURL: URL?, eventId: Int, token: String?) {
        guard let serverURL, let token else { return }
        fetch(url: serverURL.appendingPathComponent("events/\(eventId)/results"),
              token: token,
              type: [EventResult].self) { [weak self] result in
            if let res = result { self?.classifications[eventId] = res }
        }
    }
    
    /// Carica le statistiche dei giri (on-demand per il PDF)
    func fetchLapStats(serverURL: URL?, eventId: Int, token: String?) {
        guard let serverURL, let token else { return }
        fetch(url: serverURL.appendingPathComponent("events/\(eventId)/lap-stats"),
              token: token,
              type: [LapStatsResponse].self) { [weak self] result in
            if let res = result { self?.eventLapStats[eventId] = res }
        }
    }
    
    /// Carica le penalità della gara (on-demand per il PDF)
    func fetchPenalties(serverURL: URL?, eventId: Int, token: String?) {
        guard let serverURL, let token else { return }
        fetch(url: serverURL.appendingPathComponent("live/\(eventId)/penalties"),
              token: token,
              type: [RacePenalty].self) { [weak self] result in
            if let res = result { self?.eventPenalties[eventId] = res }
        }
    }

    /// Salva il tempo auto-dichiarato per un evento
    func selfDeclareResult(
        serverURL: URL?,
        eventId: Int,
        bestLapMs: Int,
        position: Int?,
        token: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let serverURL, let token else { completion(false); return }

        var req = URLRequest(url: serverURL.appendingPathComponent("events/\(eventId)/results/me/best_lap"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = ["best_lap_ms": bestLapMs]
        if let pos = position { body["position"] = pos }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        NetworkService.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data,
                      let result = try? JSONDecoder().decode(EventResult.self, from: data)
                else { completion(false); return }

                // Rimpiazza/aggiunge il risultato aggiornato localmente
                if let idx = self?.myResults.firstIndex(where: { $0.eventId == eventId && !$0.isOfficial }) {
                    self?.myResults[idx] = result
                } else {
                    self?.myResults.append(result)
                }
                completion(true)
            }
        }.resume()
    }
    
    func declareKartodromoResult(
        serverURL: URL?,
        kartodromoId: Int,
        bestLapMs: Int,
        date: Date,
        token: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let serverURL, let token else { completion(false); return }

        var req = URLRequest(url: serverURL.appendingPathComponent("kartodromi/\(kartodromoId)/results/me/best_lap"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        
        let body: [String: Any] = [
            "best_lap_ms": bestLapMs,
            "date": formatter.string(from: date)
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        NetworkService.shared.dataTask(with: req) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data,
                      let result = try? JSONDecoder().decode(KartodromoResultResponse.self, from: data)
                else { completion(false); return }

                self?.kartodromiResults.append(result)
                self?.kartodromiResults.sort { $0.date > $1.date }
                completion(true)
            }
        }.resume()
    }

    // ── Helpers interni ───────────────────────────────────────────────────────

    private func fetch<T: Decodable & Sendable>(url: URL, token: String, type: T.Type,
                                     completion: @escaping (T?) -> Void) {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        NetworkService.shared.dataTask(with: req) { data, _, _ in
            Task { @MainActor in
                guard let data else { completion(nil); return }
                let decoded = try? await BackgroundJSON.decode(T.self, from: data)
                completion(decoded)
            }
        }.resume()
    }

    func parseDate(from string: String) -> Date? {
        if let cached = dateCache[string] { return cached }
        let parsed = decodeDate(string)
        if let parsed { dateCache[string] = parsed }
        return parsed
    }

    private func decodeDate(_ string: String) -> Date? {
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFrac.date(from: string) { return d }

        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) { return d }

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(abbreviation: "UTC")
        
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df.date(from: string) { return d }
        
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = df.date(from: string) { return d }
        
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = df.date(from: string) { return d }
        
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let d = df.date(from: string) { return d }
        
        return nil
    }
}
