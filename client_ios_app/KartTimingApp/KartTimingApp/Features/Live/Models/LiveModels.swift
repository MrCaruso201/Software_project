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
        case "stop_go":
            if let s = seconds { return "Stop & Go (+\(s)s)" }
            return "Stop & Go"
        case "time_added":
            if let s = seconds { return "+\(s)s" }
            return "Tempo Aggiunto"
        default: return "Penalità"
        }
    }

    var parsedDate: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: createdAt) { return d }
        let f2 = ISO8601DateFormatter()
        return f2.date(from: createdAt)
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
        return f2.date(from: createdAt)
    }
}

// MARK: - My Kart (User)

struct MyKartResponse: Codable {
    let kartNumber: Int?
    let teamId: String?
    let teamName: String?
    let penalties: [RacePenalty]
    let messages: [RaceMessage]
    let totalPenaltySeconds: Int

    enum CodingKeys: String, CodingKey {
        case kartNumber = "kart_number"
        case teamId = "team_id"
        case teamName = "team_name"
        case penalties
        case messages
        case totalPenaltySeconds = "total_penalty_seconds"
    }

    init() {
        kartNumber = nil; teamId = nil; teamName = nil
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

    var requiresSeconds: Bool {
        action == "time_added" || action == "stop_go" || action == "custom"
    }

    var systemIcon: String {
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
    case yellowFlag  = "yellow_flag"
    case redFlag     = "red_flag"
    case greenFlag   = "green_flag"
    case info        = "info"
    case custom      = "custom"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellowFlag: return "⚠️ Bandiera Gialla"
        case .redFlag:    return "🔴 Gara Sospesa"
        case .greenFlag:  return "✅ Gara Ripresa"
        case .info:       return "📢 Informazione"
        case .custom:     return "✏️ Testo Libero"
        }
    }

    var defaultText: String {
        switch self {
        case .yellowFlag: return "Attenzione! Bandiera gialla in pista."
        case .redFlag:    return "Gara sospesa. Rallentare e portarsi ai box."
        case .greenFlag:  return "Gara ripresa. Si può procedere normalmente."
        case .info:       return ""
        case .custom:     return ""
        }
    }
}
