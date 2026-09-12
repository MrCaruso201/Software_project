import Foundation

// MARK: - Live Kart Assignment

nonisolated struct LiveKartAssignment: Identifiable, Codable, Sendable {
    let id: Int
    let eventId: Int
    let teamId: String
    let kartNumber: Int
    let teamName: String?
    let createdAt: String
    let totalPenaltySeconds: Int
    let isInPit: Bool
    let stintElapsedSeconds: Int
    let stintLastResume: String?

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case teamId = "team_id"
        case kartNumber = "kart_number"
        case teamName = "team_name"
        case createdAt = "created_at"
        case totalPenaltySeconds = "total_penalty_seconds"
        case isInPit = "is_in_pit"
        case stintElapsedSeconds = "stint_elapsed_seconds"
        case stintLastResume = "stint_last_resume"
    }

    var parsedStintLastResume: Date? {
        stintLastResume.flatMap { LiveDateCache.parse($0) }
    }
    
    var currentStintDuration: TimeInterval {
        var total = Double(stintElapsedSeconds)
        if let resumeDate = parsedStintLastResume, !isInPit {
            total += Date().timeIntervalSince(resumeDate)
        }
        return max(0, total)
    }
}

// MARK: - Race Penalty

nonisolated struct RacePenalty: Identifiable, Codable, Sendable, Equatable {
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

    var parsedDate: Date? { LiveDateCache.parse(createdAt) }
}

// MARK: - Race Message

nonisolated struct RaceMessage: Identifiable, Codable, Sendable {
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

    var parsedDate: Date? { LiveDateCache.parse(createdAt) }
}

// MARK: - Team Member Weight

nonisolated struct TeamMemberWeight: Codable, Sendable {
    let username: String?
    let weight: Double?
}

// MARK: - My Kart (User)

nonisolated struct MyKartResponse: Codable, Sendable {
    let kartNumber: Int?
    let teamId: String?
    let teamName: String?
    let weight: Double?
    let teamMembers: [TeamMemberWeight]
    let penalties: [RacePenalty]
    let messages: [RaceMessage]
    let totalPenaltySeconds: Int
    let isInPit: Bool
    let stintElapsedSeconds: Int
    let stintLastResume: String?

    enum CodingKeys: String, CodingKey {
        case kartNumber = "kart_number"
        case teamId = "team_id"
        case teamName = "team_name"
        case weight
        case teamMembers = "team_members"
        case penalties
        case messages
        case totalPenaltySeconds = "total_penalty_seconds"
        case isInPit = "is_in_pit"
        case stintElapsedSeconds = "stint_elapsed_seconds"
        case stintLastResume = "stint_last_resume"
    }
    var actualPenalties: [RacePenalty] {
        penalties.filter { !$0.isWarning }
    }

    init() {
        kartNumber = nil; teamId = nil; teamName = nil; weight = nil; teamMembers = []
        penalties = []; messages = []; totalPenaltySeconds = 0
        isInPit = false; stintElapsedSeconds = 0; stintLastResume = nil
    }

    var parsedStintLastResume: Date? {
        stintLastResume.flatMap { LiveDateCache.parse($0) }
    }
    
    var currentStintDuration: TimeInterval {
        var total = Double(stintElapsedSeconds)
        if let resumeDate = parsedStintLastResume, !isInPit {
            total += Date().timeIntervalSince(resumeDate)
        }
        return max(0, total)
    }
}

// MARK: - Preset Penalty Types

// MARK: - Penalty Type

nonisolated struct PenaltyType: Identifiable, Codable, Equatable, Sendable {
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

nonisolated private enum LiveDateCache {
    private static let cache: NSCache<NSString, NSDate> = {
        let cache = NSCache<NSString, NSDate>()
        cache.countLimit = 2048
        return cache
    }()

    static func parse(_ value: String) -> Date? {
        if let date = cache.object(forKey: value as NSString) { return date as Date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var parsed = iso.date(from: value)
        if parsed == nil {
            iso.formatOptions = [.withInternetDateTime]
            parsed = iso.date(from: value)
        }
        if parsed == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: value) { parsed = date; break }
            }
        }
        if let parsed { cache.setObject(parsed as NSDate, forKey: value as NSString) }
        return parsed
    }
}

/// Local live-session choices, independent of whether the Team tab is visible.
struct DriverSwapSelection {
    var current: String?
    var next: String?
    private var teamId: String?
    private var kartNumber: Int?
    private var wasInPit: Bool?

    mutating func update(with kart: MyKartResponse) {
        guard kart.teamId != nil || kart.kartNumber != nil else { return }
        if teamId != kart.teamId || kartNumber != kart.kartNumber {
            current = nil
            next = nil
            wasInPit = nil
        }
        teamId = kart.teamId
        kartNumber = kart.kartNumber
        let names = Set(kart.teamMembers.compactMap(\.username))
        if let current, !names.contains(current) { self.current = nil }
        if let next, !names.contains(next) { self.next = nil }
        if wasInPit == true && !kart.isInPit {
            current = next
            next = nil
        }
        wasInPit = kart.isInPit
    }
}
