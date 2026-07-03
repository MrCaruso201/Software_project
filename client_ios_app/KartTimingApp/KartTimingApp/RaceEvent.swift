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
        case createdAt = "created_at"
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
