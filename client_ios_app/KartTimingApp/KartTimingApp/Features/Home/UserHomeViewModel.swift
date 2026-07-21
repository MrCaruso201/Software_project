import Foundation
import Combine

class UserHomeViewModel: ObservableObject {
    @Published var profile: UserProfile?
    @Published var registrations: [EventRegistrationResponse] = []
    @Published var events: [RaceEvent] = []
    @Published var notifications: [AppNotification] = []

    @Published var isLoading = true

    private let readIdsKey = "readNotificationIds"

    // MARK: - Statistiche calcolate

    var totalRegistrations: Int { registrations.count }
    var confirmedRegistrations: Int { registrations.filter { $0.status == "confirmed" }.count }
    var pendingRegistrations: Int { registrations.filter { $0.status == "pending_payment" }.count }
    var waitlistRegistrations: Int { registrations.filter { $0.status == "waitlist" }.count }

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    // MARK: - Fetch

    func fetchData(serverURL: URL?, token: String?) {
        guard let serverURL = serverURL, let token = token else {
            DispatchQueue.main.async { self.isLoading = false }
            return
        }

        isLoading = true

        let group = DispatchGroup()

        // Fetch User Profile
        group.enter()
        var reqMe = URLRequest(url: serverURL.appendingPathComponent("auth/me"))
        reqMe.httpMethod = "GET"
        reqMe.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: reqMe) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
                    self.profile = p
                }
                group.leave()
            }
        }.resume()

        // Fetch Registrations
        group.enter()
        var reqReg = URLRequest(url: serverURL.appendingPathComponent("events/registrations/me"))
        reqReg.httpMethod = "GET"
        reqReg.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: reqReg) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let regs = try? JSONDecoder().decode([EventRegistrationResponse].self, from: data) {
                    self.registrations = regs
                }
                group.leave()
            }
        }.resume()

        // Fetch Events
        group.enter()
        var reqEv = URLRequest(url: serverURL.appendingPathComponent("events"))
        reqEv.httpMethod = "GET"
        reqEv.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: reqEv) { data, _, _ in
            DispatchQueue.main.async {
                if let data = data, let evs = try? JSONDecoder().decode([RaceEvent].self, from: data) {
                    self.events = evs
                }
                group.leave()
            }
        }.resume()

        group.notify(queue: .main) {
            self.isLoading = false
            self.buildNotifications()
        }
    }

    // MARK: - Notifiche

    /// Marca una notifica come letta e persiste l'ID in UserDefaults.
    func markNotificationRead(id: String) {
        var readIds = Set(UserDefaults.standard.stringArray(forKey: readIdsKey) ?? [])
        guard !readIds.contains(id) else { return }
        readIds.insert(id)
        UserDefaults.standard.set(Array(readIds), forKey: readIdsKey)
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].isRead = true
        }
    }

    /// Costruisce l'array di notifiche dai dati già scaricati.
    func buildNotifications() {
        let readIds = Set(UserDefaults.standard.stringArray(forKey: readIdsKey) ?? [])
        let now = Date()
        let calendar = Calendar.current
        var result: [AppNotification] = []

        // 1. Pagamento in attesa
        for reg in registrations where reg.status == "pending_payment" {
            if let event = events.first(where: { $0.id == reg.eventId }) {
                let stableId = "pending_\(reg.eventId)"
                result.append(AppNotification(
                    id: stableId,
                    type: .pendingPayment(event: event),
                    title: "Pagamento in attesa",
                    message: "Completa il pagamento per \"\(event.title)\"",
                    isRead: readIds.contains(stableId)
                ))
            }
        }

        // 2. Lista d'attesa
        for reg in registrations where reg.status == "waitlist" {
            if let event = events.first(where: { $0.id == reg.eventId }) {
                let stableId = "waitlist_\(reg.eventId)"
                result.append(AppNotification(
                    id: stableId,
                    type: .waitlist(event: event),
                    title: "Lista d'attesa",
                    message: "Sei in lista d'attesa per \"\(event.title)\"",
                    isRead: readIds.contains(stableId)
                ))
            }
        }

        // 3. Promemoria eventi imminenti (confermati, entro 7 giorni)
        let confirmedEventIds = Set(registrations.filter { $0.status == "confirmed" }.map { $0.eventId })
        for eventId in confirmedEventIds {
            if let event = events.first(where: { $0.id == eventId }),
               let date = parseDate(from: event.eventDate) {
                let daysLeft = calendar.dateComponents([.day], from: now, to: date).day ?? Int.max
                if daysLeft >= 0 && daysLeft <= 7 {
                    let stableId = "upcoming_\(eventId)"
                    let dayMsg: String
                    if daysLeft == 0 {
                        dayMsg = "L'evento è oggi!"
                    } else {
                        dayMsg = "L'evento è tra \(daysLeft) giorn\(daysLeft == 1 ? "o" : "i")"
                    }
                    result.append(AppNotification(
                        id: stableId,
                        type: .upcomingEvent(event: event, daysLeft: daysLeft),
                        title: "Evento imminente",
                        message: "\(event.title) – \(dayMsg)",
                        isRead: readIds.contains(stableId)
                    ))
                }
            }
        }

        // 4. Nuovi eventi (creati negli ultimi 7 giorni, non iscritto)
        let registeredEventIds = Set(registrations.map { $0.eventId })
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        for event in events where !registeredEventIds.contains(event.id) {
            if let createdDate = parseDate(from: event.createdAt), createdDate >= sevenDaysAgo {
                let stableId = "new_event_\(event.id)"
                result.append(AppNotification(
                    id: stableId,
                    type: .newEvent(event: event),
                    title: "Nuovo evento disponibile",
                    message: "\"\(event.title)\" – \(event.formattedDate)",
                    isRead: readIds.contains(stableId)
                ))
            }
        }

        self.notifications = result
    }

    // MARK: - Date parsing helper

    private func parseDate(from string: String) -> Date? {
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFull.date(from: string) { return d }

        let isoBasic = ISO8601DateFormatter()
        if let d = isoBasic.date(from: string) { return d }

        let df1 = DateFormatter()
        df1.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = df1.date(from: string) { return d }

        let df2 = DateFormatter()
        df2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let d = df2.date(from: string) { return d }

        return nil
    }
}

struct UserProfile: Codable {
    let id: Int
    let username: String
    let firstName: String?
    let lastName: String?
    let profilePictureURL: String?
    let email: String
    let role: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, username, email, role
        case firstName = "first_name"
        case lastName = "last_name"
        case profilePictureURL = "profile_picture_url"
        case createdAt = "created_at"
    }
}
