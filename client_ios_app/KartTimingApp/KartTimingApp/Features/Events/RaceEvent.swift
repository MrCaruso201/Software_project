import Foundation

struct RaceEvent: Identifiable, Codable {
    let id: Int
    let title: String
    let eventDate: String
    let registrationDeadline: String?
    let location: String
    let maxParticipants: Int?
    let maxGroups: Int?
    let minPeoplePerGroup: Int?
    let maxPeoplePerGroup: Int?
    let registrationCost: Double?
    let weightLimit: Double?
    let description: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case eventDate = "event_date"
        case registrationDeadline = "registration_deadline"
        case location
        case maxParticipants = "max_participants"
        case maxGroups = "max_groups"
        case minPeoplePerGroup = "min_people_per_group"
        case maxPeoplePerGroup = "max_people_per_group"
        case registrationCost = "registration_cost"
        case weightLimit = "weight_limit"
        case description
        case createdAt = "created_at"
    }

    /// True se la gara è a squadre (max_people_per_group > 1)
    var isTeamEvent: Bool {
        return (maxPeoplePerGroup ?? 1) > 1
    }

    var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: eventDate) {
            let outFormatter = DateFormatter()
            outFormatter.dateStyle = .medium
            outFormatter.timeStyle = .short
            outFormatter.locale = Locale(identifier: "it_IT")
            return outFormatter.string(from: date)
        }
        
        let fallbackFormatter = ISO8601DateFormatter()
        if let date = fallbackFormatter.date(from: eventDate) {
            let outFormatter = DateFormatter()
            outFormatter.dateStyle = .medium
            outFormatter.timeStyle = .short
            outFormatter.locale = Locale(identifier: "it_IT")
            return outFormatter.string(from: date)
        }
        
        return String(eventDate.prefix(10))
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
    
    var id: String { teamId }
    
    enum CodingKeys: String, CodingKey {
        case teamId = "team_id"
        case teamName = "team_name"
        case eventId = "event_id"
        case members
        case overallStatus = "overall_status"
    }
}
