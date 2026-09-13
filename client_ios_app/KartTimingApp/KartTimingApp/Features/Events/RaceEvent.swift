import Foundation

nonisolated struct RaceEvent: Identifiable, Codable, Sendable {
    let id: Int
    let title: String
    let eventDate: String
    let registrationDeadline: String?
    let daysBeforeDeadline: Int?
    let location: String
    let maxParticipants: Int?
    let minPeoplePerGroup: Int?
    let maxPeoplePerGroup: Int?
    let registrationCost: Double?
    let weightLimit: Double?
    let kart: String?
    let description: String?
    let raceDuration: Int?
    let maxStintDuration: Int?
    let createdAt: String
    /// "scheduled" | "started" | "finished"
    let status: String
    let sessionName: String?
    let releaseFormText: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case eventDate = "event_date"
        case registrationDeadline = "registration_deadline"
        case daysBeforeDeadline = "days_before_deadline"
        case location
        case maxParticipants = "max_participants"
        case minPeoplePerGroup = "min_people_per_group"
        case maxPeoplePerGroup = "max_people_per_group"
        case registrationCost = "registration_cost"
        case weightLimit = "weight_limit"
        case kart
        case description
        case raceDuration = "race_duration"
        case maxStintDuration = "max_stint_duration"
        case createdAt = "created_at"
        case status
        case sessionName = "session_name"
        case releaseFormText = "release_form_text"
    }

    /// True se la gara è a squadre (min_people_per_group >= 2 oppure max_people_per_group > 1)
    var isTeamEvent: Bool {
        return (minPeoplePerGroup ?? 1) >= 2 || (maxPeoplePerGroup ?? 1) > 1
    }

    /// Data deadline parsata come oggetto Date
    var deadlineObject: Date? {
        guard let raw = registrationDeadline, !raw.isEmpty else { return nil }
        return Self.parseDate(from: raw)
    }

    /// Stato della deadline rispetto al momento attuale.
    enum DeadlineStatus {
        case none           // Nessuna deadline impostata
        case open           // Aperta, scade tra più di 3 giorni
        case approaching    // In scadenza (entro 3 giorni)
        case passed         // Scaduta
    }

    /// Soglia in secondi per considerare la deadline "imminente" (3 giorni)
    private static let approachingThreshold: TimeInterval = 3 * 24 * 60 * 60

    var deadlineStatus: DeadlineStatus {
        guard let dl = deadlineObject else { return .none }
        let now = Date()
        if now > dl { return .passed }
        if dl.timeIntervalSince(now) <= Self.approachingThreshold { return .approaching }
        return .open
    }

    /// True se la deadline è già scaduta
    var isDeadlinePassed: Bool { deadlineStatus == .passed }

    /// True se la deadline è imminente (entro 3 giorni)
    var isDeadlineApproaching: Bool { deadlineStatus == .approaching }

    var formattedDate: String {
        if let date = dateObject {
            return Self.format(date)
        }
        return eventDate
    }
    
    var formattedDateNoTime: String {
        if let date = dateObject {
            return Self.formatNoTime(date)
        }
        return eventDate
    }
    
    var dateObject: Date? {
        Self.parseDate(from: eventDate)
    }
    
    private static func parseDate(from string: String) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: string) { return d }
        
        let isoFallback = ISO8601DateFormatter()
        if let d = isoFallback.date(from: string) { return d }
        
        let df1 = DateFormatter()
        df1.timeZone = TimeZone(abbreviation: "UTC")
        df1.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df1.date(from: string) { return d }
        
        let df2 = DateFormatter()
        df2.timeZone = TimeZone(abbreviation: "UTC")
        df2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = df2.date(from: string) { return d }
        
        let df3 = DateFormatter()
        df3.timeZone = TimeZone(abbreviation: "UTC")
        df3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = df3.date(from: string) { return d }
        
        let df4 = DateFormatter()
        df4.timeZone = TimeZone(abbreviation: "UTC")
        df4.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        if let d = df4.date(from: string) { return d }
        
        return nil
    }

    private static func format(_ date: Date) -> String {
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "d MMM yyyy, HH:mm"
        outFormatter.locale = Locale(identifier: "it_IT")
        return outFormatter.string(from: date)
    }

    private static func formatNoTime(_ date: Date) -> String {
        let outFormatter = DateFormatter()
        outFormatter.dateFormat = "d MMM yyyy"
        outFormatter.locale = Locale(identifier: "it_IT")
        return outFormatter.string(from: date)
    }
}

// MARK: - Registration Response (singola iscrizione)

nonisolated struct EventRegistrationResponse: Codable, Sendable {
    let id: Int
    let userId: Int?
    let eventId: Int
    let status: String
    let teamName: String?
    let teamId: String?
    let isTeamLeader: Bool
    let memberEmail: String?
    let createdAt: String
    let hasSignedRelease: Bool?
    var weight: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case status
        case teamName = "team_name"
        case teamId = "team_id"
        case isTeamLeader = "is_team_leader"
        case memberEmail = "member_email"
        case createdAt = "created_at"
        case hasSignedRelease = "has_signed_release"
        case weight
    }
}

// MARK: - Registration With User Response (per admin - vista flat)

nonisolated struct EventRegistrationWithUserResponse: Codable, Identifiable, Sendable {
    let id: Int
    let userId: Int?
    let eventId: Int
    let status: String
    let teamName: String?
    let teamId: String?
    let isTeamLeader: Bool
    let memberEmail: String?
    let createdAt: String
    let username: String?
    let email: String?
    let profilePictureUrl: String?
    let hasSignedRelease: Bool?
    var weight: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case status
        case teamName = "team_name"
        case teamId = "team_id"
        case isTeamLeader = "is_team_leader"
        case memberEmail = "member_email"
        case createdAt = "created_at"
        case username
        case email
        case profilePictureUrl = "profile_picture_url"
        case hasSignedRelease = "has_signed_release"
        case weight
    }
}

// MARK: - Team Registration Response (per admin - vista raggruppata per team)

nonisolated struct TeamMemberResponse: Codable, Identifiable, Sendable {
    let registrationId: Int
    let userId: Int?
    let username: String?
    let email: String?
    let isTeamLeader: Bool
    let status: String
    let profilePictureUrl: String?
    let hasSignedRelease: Bool?
    var weight: Double?
    
    var id: Int { registrationId }
    
    enum CodingKeys: String, CodingKey {
        case registrationId = "registration_id"
        case userId = "user_id"
        case username
        case email
        case isTeamLeader = "is_team_leader"
        case status
        case profilePictureUrl = "profile_picture_url"
        case hasSignedRelease = "has_signed_release"
        case weight
    }
}

nonisolated struct TeamRegistrationResponse: Codable, Identifiable, Sendable {
    let teamId: String
    let teamName: String
    let eventId: Int
    let members: [TeamMemberResponse]
    let overallStatus: String
    let acceptsExtraPilots: Bool
    
    var id: String { teamId }
    
    enum CodingKeys: String, CodingKey {
        case teamId = "team_id"
        case teamName = "team_name"
        case eventId = "event_id"
        case members
        case overallStatus = "overall_status"
        case acceptsExtraPilots = "accepts_extra_pilots"
    }
}

// MARK: - Signed Release Response (per admin)

nonisolated struct SignedReleaseResponse: Codable, Identifiable, Sendable {
    let id: Int?
    let userId: Int?
    let username: String?
    let firstName: String?
    let lastName: String?
    let signedAt: String?
    let codiceFiscale: String?
    let birthDate: String?
    let residence: String?
    let signatureBase64: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case username
        case firstName = "first_name"
        case lastName = "last_name"
        case signedAt = "signed_at"
        case codiceFiscale = "codice_fiscale"
        case birthDate = "birth_date"
        case residence = "residence"
        case signatureBase64 = "signature_base64"
    }
}
