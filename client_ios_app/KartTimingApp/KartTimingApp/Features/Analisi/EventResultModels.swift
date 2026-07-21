import Foundation

// MARK: - KartodromoResultResponse

struct KartodromoResultResponse: Identifiable, Codable {
    let id: Int
    let userId: Int
    let kartodromoId: Int
    let bestLapMs: Int
    let date: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case kartodromoId = "kartodromo_id"
        case bestLapMs = "best_lap_ms"
        case date
        case createdAt = "created_at"
    }
    
    var formattedBestLap: String {
        let minutes = bestLapMs / 60_000
        let seconds = (bestLapMs % 60_000) / 1_000
        let millis  = bestLapMs % 1_000
        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, millis)
        } else {
            return String(format: "%d.%03d", seconds, millis)
        }
    }
}

// MARK: - EventResult

/// Risultato di un pilota in una gara.
/// `isOfficial = true`  → inserito dall'admin (via CSV)
/// `isOfficial = false` → auto-dichiarato dal pilota
struct EventResult: Identifiable, Codable {
    let id: Int
    let eventId: Int
    let userId: Int?
    let driverName: String?
    let memberEmail: String?
    let position: Int?
    let bestLapMs: Int?
    let gap: String?
    let laps: Int?
    let isOfficial: Bool
    let teamId: String?
    let teamName: String?
    let note: String?
    let username: String?
    let profilePictureUrl: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventId           = "event_id"
        case userId            = "user_id"
        case driverName        = "driver_name"
        case memberEmail       = "member_email"
        case position
        case bestLapMs         = "best_lap_ms"
        case gap
        case laps
        case isOfficial        = "is_official"
        case teamId            = "team_id"
        case teamName          = "team_name"
        case note
        case username
        case profilePictureUrl = "profile_picture_url"
        case createdAt         = "created_at"
    }

    /// Miglior giro formattato come "M:SS.mmm"
    var formattedBestLap: String? {
        guard let ms = bestLapMs else { return nil }
        let minutes = ms / 60_000
        let seconds = (ms % 60_000) / 1_000
        let millis  = ms % 1_000
        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, millis)
        } else {
            return String(format: "%d.%03d", seconds, millis)
        }
    }

    /// Emoji medaglia + numero posizione
    var positionLabel: String {
        switch position {
        case 1:  return "🥇 1°"
        case 2:  return "🥈 2°"
        case 3:  return "🥉 3°"
        default:
            if let p = position { return "\(p)°" }
            return "—"
        }
    }

    var displayName: String {
        driverName ?? teamName ?? username ?? memberEmail ?? "Sconosciuto"
    }
}

// MARK: - CircuitStat

/// Statistiche aggregate per un singolo circuito, costruite client-side.
struct CircuitStat: Identifiable {
    let id: String      // nome del circuito (usato come chiave)
    let circuitName: String
    var kartodromoId: Int?
    var kartodromoResults: [KartodromoResultResponse] = []
    var entries: [Entry]

    var racesCount: Int   { entries.count }
    var bestEventLapMs: Int?  { entries.compactMap { $0.result?.bestLapMs }.min() }
    var bestSelfLapMs: Int?      { kartodromoResults.compactMap { $0.bestLapMs }.min() }
    var bestPosition: Int?       { entries.compactMap { $0.result?.position }.min() }

    var hasAnyLapData: Bool {
        !kartodromoResults.isEmpty || entries.contains { $0.result?.bestLapMs != nil }
    }

    /// Punti per il grafico andamento tempi, ordinati per data
    var chartPoints: [ChartPoint] {
        var points: [ChartPoint] = []
        
        // Punti delle gare
        points.append(contentsOf: entries.compactMap { entry -> ChartPoint? in
            guard let r = entry.result, let ms = r.bestLapMs else { return nil }
            return ChartPoint(date: entry.eventDate, lapSeconds: Double(ms) / 1000.0,
                              isOfficial: true, eventTitle: entry.eventTitle)
        })
        
        // Punti delle prove libere
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        points.append(contentsOf: kartodromoResults.compactMap { kr -> ChartPoint? in
            guard let date = formatter.date(from: kr.date) else { return nil }
            return ChartPoint(date: date, lapSeconds: Double(kr.bestLapMs) / 1000.0,
                              isOfficial: false, eventTitle: "Prova Libera")
        })
        
        return points.sorted { $0.date < $1.date }
    }

    // MARK: – Nested types

    struct Entry: Identifiable {
        let id: Int             // event.id
        let eventTitle: String
        let eventDate: Date
        let result: EventResult?

        var bestLapMs: Int? { result?.bestLapMs }
        var position: Int?  { result?.position }
    }

    struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let lapSeconds: Double
        let isOfficial: Bool
        let eventTitle: String
    }
}

// MARK: - CSV Import result (lato iOS)

struct CSVImportResult {
    let imported: Int
    let errors: [String]
}
