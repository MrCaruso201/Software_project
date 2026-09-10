import Foundation

// MARK: - Server Notification API Model

nonisolated struct ServerNotification: Codable, Sendable {
    let id: Int
    let userId: Int
    let eventId: Int?
    let type: String
    let title: String
    let message: String
    let isRead: Bool
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, type, title, message
        case userId = "user_id"
        case eventId = "event_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

// MARK: - Notification Type

enum AppNotificationType {
    case pendingPayment(event: RaceEvent)
    case waitlist(event: RaceEvent)
    case upcomingEvent(event: RaceEvent, daysLeft: Int)
    case newEvent(event: RaceEvent)
    case adminAction(serverNotif: ServerNotification, event: RaceEvent?)
}

// MARK: - AppNotification Model

struct AppNotification: Identifiable {
    /// ID stabile basato sul contenuto (usato per tracciare lo stato "letto" in UserDefaults)
    let id: String
    let type: AppNotificationType
    let title: String
    let message: String
    var isRead: Bool
    let timestamp: Date

    /// Evento associato alla notifica (per aprire sheet pagamento, dettaglio, ecc.)
    var associatedEvent: RaceEvent? {
        switch type {
        case .pendingPayment(let event): return event
        case .waitlist(let event):       return event
        case .upcomingEvent(let event, _): return event
        case .newEvent(let event):       return event
        case .adminAction(_, let event): return event
        }
    }

    var iconName: String {
        switch type {
        case .pendingPayment: return "exclamationmark.triangle.fill"
        case .waitlist:       return "clock.fill"
        case .upcomingEvent:  return "calendar.badge.clock"
        case .newEvent:       return "star.fill"
        case .adminAction(let serverNotif, _):
            switch serverNotif.type {
            case "registration_accepted", "registration_confirmed": return "checkmark.seal.fill"
            case "registration_unconfirmed": return "exclamationmark.triangle.fill"
            case "moved_to_waitlist": return "clock.fill"
            case "registration_deleted", "release_rejected": return "xmark.octagon.fill"
            default: return "bell.fill"
            }
        }
    }

    var iconColor: String {
        switch type {
        case .pendingPayment: return "orange"
        case .waitlist:       return "purple"
        case .upcomingEvent:  return "yellow"
        case .newEvent:       return "green"
        case .adminAction(let serverNotif, _):
            switch serverNotif.type {
            case "registration_accepted", "registration_confirmed": return "green"
            case "registration_unconfirmed": return "orange"
            case "moved_to_waitlist": return "purple"
            case "registration_deleted", "release_rejected": return "red"
            default: return "blue"
            }
        }
    }
}
