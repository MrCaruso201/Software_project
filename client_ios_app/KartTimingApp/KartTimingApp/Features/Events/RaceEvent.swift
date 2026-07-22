import Foundation

struct RaceEvent: Identifiable, Codable {
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
    }

    /// True se la gara è a squadre (max_people_per_group > 1)
    var isTeamEvent: Bool {
        return (maxPeoplePerGroup ?? 1) > 1
    }

    var formattedDate: String {
        if let date = dateObject {
            return Self.format(date)
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
        df1.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df1.date(from: string) { return d }
        
        let df2 = DateFormatter()
        df2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = df2.date(from: string) { return d }
        
        let df3 = DateFormatter()
        df3.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        if let d = df3.date(from: string) { return d }
        
        let df4 = DateFormatter()
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
}

// MARK: - Registration Response (singola iscrizione)

struct EventRegistrationResponse: Codable {
    let id: Int
    let userId: Int?
    let eventId: Int
    let status: String
    let teamName: String?
    let teamId: String?
    let isTeamLeader: Bool
    let memberEmail: String?
    let createdAt: String
    
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
    }
}

// MARK: - Registration With User Response (per admin - vista flat)

struct EventRegistrationWithUserResponse: Codable, Identifiable {
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
    }
}

// MARK: - Team Registration Response (per admin - vista raggruppata per team)

struct TeamMemberResponse: Codable, Identifiable {
    let registrationId: Int
    let userId: Int?
    let username: String?
    let email: String?
    let isTeamLeader: Bool
    let status: String
    let profilePictureUrl: String?
    
    var id: Int { registrationId }
    
    enum CodingKeys: String, CodingKey {
        case registrationId = "registration_id"
        case userId = "user_id"
        case username
        case email
        case isTeamLeader = "is_team_leader"
        case status
        case profilePictureUrl = "profile_picture_url"
    }
}

struct TeamRegistrationResponse: Codable, Identifiable {
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
