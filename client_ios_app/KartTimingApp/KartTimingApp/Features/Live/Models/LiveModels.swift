import Foundation

// MARK: - Live Kart Assignment

struct LiveKartAssignment: Identifiable, Codable {
    let id: Int
    let eventId: Int
    let teamId: String
    let kartNumber: Int
    let teamName: String?
    let createdAt: String
    let totalPenaltySeconds: Int

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case teamId = "team_id"
        case kartNumber = "kart_number"
        case teamName = "team_name"
        case createdAt = "created_at"
        case totalPenaltySeconds = "total_penalty_seconds"
    }
}

// MARK: - Race Penalty

struct RacePenalty: Identifiable, Codable {
    let id: Int
    let eventId: Int
    let kartNumber: Int
    let penaltyType: String   // "drive_through" | "stop_go" | "time_added" | "generic"
    let seconds: Int?
    let note: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case kartNumber = "kart_number"
        case penaltyType = "penalty_type"
        case seconds
        case note
        case createdAt = "created_at"
    }

    var displayLabel: String {
        switch penaltyType {
        case "drive_through": return "Drive-Through"
        case "stop_go": return seconds != nil ? "Stop & Go (+\(seconds!)s)" : "Stop & Go"
        case "time_added": return seconds != nil ? "Tempo Aggiunto (+\(seconds!)s)" : "Tempo Aggiunto"
        case "false_start": return seconds != nil ? "Falsa Partenza (+\(seconds!)s)" : "Falsa Partenza"
        case "aggressive_driving": return seconds != nil ? "Guida Aggressiva (+\(seconds!)s)" : "Guida Aggressiva"
        case "stint_time": return seconds != nil ? "Stint (+\(seconds!)s)" : "Stint"
        case "pit_stop_time": return seconds != nil ? "Pit Stop (+\(seconds!)s)" : "Pit Stop"
        case "weight": return seconds != nil ? "Peso (+\(seconds!)s)" : "Peso"
        case "directive": return seconds != nil ? "Direttive (+\(seconds!)s)" : "Direttive"
        case "custom": return seconds != nil ? "Penalità (+\(seconds!)s)" : "Penalità Custom"
        case "drop_position": return "Drop 1 Position"
        case "warning_track_limits": return "Avviso (Track Limits)"
        case "warning_aggressive_driving": return "Avviso (Guida Aggressiva)"
        case "track_limits_10s": return seconds != nil ? "Track Limits (+\(seconds!)s)" : "Track Limits (+10s)"
        case "black_flag": return "Bandiera Nera (Espulsione)"
        case "blue_flag": return "Bandiera Blu (Doppiaggio)"
        default: return "Penalità"
        }
    }

    var isWarning: Bool {
        return penaltyType == "drop_position"
            || penaltyType == "warning_track_limits"
            || penaltyType == "warning_aggressive_driving"
            || penaltyType == "blue_flag"
    }

    var parsedDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: createdAt) { return d }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: createdAt) { return d }
        
        let df = DateFormatter()
        df.timeZone = TimeZone(abbreviation: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = df.date(from: createdAt) { return d }
        
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: createdAt)
    }
}

// MARK: - Race Message

struct RaceMessage: Identifiable, Codable {
    let id: Int
    let eventId: Int
    let targetKart: Int?     // nil = broadcast
    let messageType: String  // "yellow_flag" | "red_flag" | "green_flag" | "info" | "custom"
    let text: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case targetKart = "target_kart"
        case messageType = "message_type"
        case text
        case createdAt = "created_at"
    }

    var isBroadcast: Bool { targetKart == nil }

    var parsedDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: createdAt) { return d }
        let f2 = ISO8601DateFormatter()
        if let d = f2.date(from: createdAt) { return d }
        
        let df = DateFormatter()
        df.timeZone = TimeZone(abbreviation: "UTC")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = df.date(from: createdAt) { return d }
        
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return df.date(from: createdAt)
    }
}

// MARK: - Team Member Weight

struct TeamMemberWeight: Codable {
    let username: String?
    let weight: Double?
}

// MARK: - My Kart (User)

struct MyKartResponse: Codable {
    let kartNumber: Int?
    let teamId: String?
    let teamName: String?
    let weight: Double?
    let teamMembers: [TeamMemberWeight]
    let penalties: [RacePenalty]
    let messages: [RaceMessage]
    let totalPenaltySeconds: Int

    enum CodingKeys: String, CodingKey {
        case kartNumber = "kart_number"
        case teamId = "team_id"
        case teamName = "team_name"
        case weight
        case teamMembers = "team_members"
        case penalties
        case messages
        case totalPenaltySeconds = "total_penalty_seconds"
    }
    var actualPenalties: [RacePenalty] {
        penalties.filter { !$0.isWarning }
    }

    init() {
        kartNumber = nil; teamId = nil; teamName = nil; weight = nil; teamMembers = []
        penalties = []; messages = []; totalPenaltySeconds = 0
    }
}

// MARK: - Preset Penalty Types

// MARK: - Penalty Type

struct PenaltyType: Identifiable, Codable, Equatable {
    let id: Int
    let code: String
    let name: String
    let action: String
    let defaultSeconds: Int?
    let warningThreshold: Int?
    let autoPenaltyCode: String?
    
    enum CodingKeys: String, CodingKey {
        case id, code, name, action
        case defaultSeconds = "default_seconds"
        case warningThreshold = "warning_threshold"
        case autoPenaltyCode = "auto_penalty_code"
    }

    var isWarning: Bool {
        // Basato sul codice, non sull'action (black_flag è una penalità nonostante action=drive_through)
        return code == "drop_position"
            || code == "warning_track_limits"
            || code == "warning_aggressive_driving"
            || code == "blue_flag"
    }

    /// Solo penalità personalizzata e avviso generico possono essere modificati (secondi/nota liberi)
    var isCustomizable: Bool {
        return code == "custom" || code == "drop_position"
    }

    var requiresSeconds: Bool {
        isCustomizable && (action == "time_added" || action == "stop_go" || action == "custom")
    }

    var systemIcon: String {
        switch code {
        case "black_flag": return "xmark.circle.fill"
        default: break
        }
        switch action {
        case "drive_through": return "arrow.right.circle.fill"
        case "stop_go":       return "stop.circle.fill"
        case "time_added":    return "plus.circle.fill"
        case "warning":       return "exclamationmark.bubble.fill"
        case "custom":        return "exclamationmark.triangle.fill"
        default:              return "flag.fill"
        }
    }
}

// MARK: - Preset Message Types

enum MessagePreset: String, CaseIterable, Identifiable {
    case yellowFlag      = "yellow_flag"
    case redFlag         = "red_flag"
    case greenFlag       = "green_flag"
    case checkeredFlag   = "checkered_flag"
    case info            = "info"
    case custom          = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellowFlag:    return "⚠️ Bandiera Gialla"
        case .redFlag:       return "🔴 Gara Sospesa"
        case .greenFlag:     return "✅ Gara Ripresa"
        case .checkeredFlag: return "🏁 Bandiera a Scacchi"
        case .info:          return "📢 Informazione"
        case .custom:        return "✏️ Testo Libero"
        }
    }

    var defaultText: String {
        switch self {
        case .yellowFlag:    return "Attenzione! Bandiera gialla in pista."
        case .redFlag:       return "Gara sospesa. Rallentare e portarsi ai box."
        case .greenFlag:     return "Gara ripresa. Si può procedere normalmente."
        case .checkeredFlag: return "Gara terminata. Rientrate ai box."
        case .info:       return ""
        case .custom:     return ""
        }
    }
}
