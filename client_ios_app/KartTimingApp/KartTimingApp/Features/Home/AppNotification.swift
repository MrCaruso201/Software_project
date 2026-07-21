import Foundation

// MARK: - Notification Type

enum AppNotificationType {
    case pendingPayment(event: RaceEvent)
    case waitlist(event: RaceEvent)
    case upcomingEvent(event: RaceEvent, daysLeft: Int)
    case newEvent(event: RaceEvent)
}

// MARK: - AppNotification Model

struct AppNotification: Identifiable {
    /// ID stabile basato sul contenuto (usato per tracciare lo stato "letto" in UserDefaults)
    let id: String
    let type: AppNotificationType
    let title: String
    let message: String
    var isRead: Bool

    /// Evento associato alla notifica (per aprire sheet pagamento, dettaglio, ecc.)
    var associatedEvent: RaceEvent? {
        switch type {
        case .pendingPayment(let event): return event
        case .waitlist(let event):       return event
        case .upcomingEvent(let event, _): return event
        case .newEvent(let event):       return event
        }
    }

    var iconName: String {
        switch type {
        case .pendingPayment: return "exclamationmark.triangle.fill"
        case .waitlist:       return "clock.fill"
        case .upcomingEvent:  return "calendar.badge.clock"
        case .newEvent:       return "star.fill"
        }
    }

    var iconColor: String {
        switch type {
        case .pendingPayment: return "orange"
        case .waitlist:       return "purple"
        case .upcomingEvent:  return "yellow"
        case .newEvent:       return "green"
        }
    }
}
