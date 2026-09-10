import Foundation
import Combine

class UserHomeViewModel: ObservableObject {
    @Published var profile: UserProfile?
    @Published var registrations: [EventRegistrationResponse] = []
    @Published var events: [RaceEvent] = []
    @Published var notifications: [AppNotification] = []
    var serverNotifications: [ServerNotification] = []
    var currentServerURL: URL?
    var currentToken: String?

    @Published var isLoading = true

    private let readIdsKey = "readNotificationIds"

    // MARK: - Statistiche calcolate

    var totalRegistrations: Int { registrations.count }
    var confirmedRegistrations: Int { registrations.filter { $0.status == "confirmed" }.count }
    var pendingRegistrations: Int { registrations.filter { $0.status == "pending_payment" }.count }
    var waitlistRegistrations: Int { registrations.filter { $0.status == "waitlist" }.count }

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    // MARK: - Fetch

    func fetchData(serverURL: URL?, token: String?, forceRefresh: Bool = false, completion: (() -> Void)? = nil) {
        guard let serverURL = serverURL, let token = token else {
            Task { @MainActor in self.isLoading = false }
            return
        }

        isLoading = profile == nil
        self.currentServerURL = serverURL
        self.currentToken = token

        let group = DispatchGroup()

        // Fetch User Profile
        group.enter()
        var reqMe = URLRequest(url: serverURL.appendingPathComponent("auth/me"))
        reqMe.httpMethod = "GET"
        reqMe.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        NetworkService.shared.dataTask(with: reqMe, cacheFor: 15, forceRefresh: forceRefresh) { data, _, _ in
            Task { @MainActor in
                if let data = data, let p = try? await BackgroundJSON.decode(UserProfile.self, from: data) {
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
        NetworkService.shared.dataTask(with: reqReg, cacheFor: 15, forceRefresh: forceRefresh) { data, _, _ in
            Task { @MainActor in
                if let data = data, let regs = try? await BackgroundJSON.decode([EventRegistrationResponse].self, from: data) {
                    self.registrations = regs
                }
                group.leave()
            }
        }.resume()


        // Fetch Server Notifications
        group.enter()
        var reqNotif = URLRequest(url: serverURL.appendingPathComponent("notifications/me"))
        reqNotif.httpMethod = "GET"
        reqNotif.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        NetworkService.shared.dataTask(with: reqNotif, cacheFor: 15, forceRefresh: forceRefresh) { data, _, _ in
            Task { @MainActor in
                if let data = data, let notifs = try? await BackgroundJSON.decode([ServerNotification].self, from: data) {
                    self.serverNotifications = notifs
                }
                group.leave()
            }
        }.resume()

        // Fetch Events
        group.enter()
        var reqEv = URLRequest(url: serverURL.appendingPathComponent("events"))
        reqEv.httpMethod = "GET"
        reqEv.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        NetworkService.shared.dataTask(with: reqEv, cacheFor: 15, forceRefresh: forceRefresh) { data, _, _ in
            Task { @MainActor in
                if let data = data, let evs = try? await BackgroundJSON.decode([RaceEvent].self, from: data) {
                    self.events = evs
                }
                group.leave()
            }
        }.resume()

        group.notify(queue: .main) {
            self.isLoading = false
            self.buildNotifications()
            completion?()
        }
    }

    // MARK: - Notifiche

    /// Marca una notifica come letta e persiste l'ID in UserDefaults.

    func deleteAllNotifications() {
        if let url = currentServerURL, let token = currentToken {
            var req = URLRequest(url: url.appendingPathComponent("notifications/me"))
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            NetworkService.shared.dataTask(with: req).resume()
        }
        Task { @MainActor in
            // Save current IDs to cleared list
            var clearedIds = Set(UserDefaults.standard.stringArray(forKey: "clearedNotificationIds") ?? [])
            for notif in self.notifications {
                clearedIds.insert(notif.id)
            }
            UserDefaults.standard.set(Array(clearedIds), forKey: "clearedNotificationIds")
            
            self.serverNotifications.removeAll()
            self.buildNotifications()
        }
    }

    func markNotificationRead(id: String) {
        if id.hasPrefix("server_") {
            let serverIdStr = id.replacingOccurrences(of: "server_", with: "")
            if let serverId = Int(serverIdStr), let serverURL = currentServerURL, let token = currentToken {
                var reqRead = URLRequest(url: serverURL.appendingPathComponent("notifications/\(serverId)/read"))
                reqRead.httpMethod = "POST"
                reqRead.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                NetworkService.shared.dataTask(with: reqRead) { _, _, _ in }.resume()
            }
        }
        
        var readIds = Set(UserDefaults.standard.stringArray(forKey: readIdsKey) ?? [])
        guard !readIds.contains(id) else { return }
        readIds.insert(id)
        UserDefaults.standard.set(Array(readIds), forKey: readIdsKey)
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx].isRead = true
        }
    }

    /// Elimina una singola notifica e nasconde quelle locali se corrispondono
    func deleteSingleNotification(id: String) {
        if id.hasPrefix("server_") {
            // È una notifica server, eliminala via API
            let sIdStr = id.replacingOccurrences(of: "server_", with: "")
            if let serverNotifId = Int(sIdStr), let url = currentServerURL?.appendingPathComponent("notifications/\(serverNotifId)"), let token = UserDefaults.standard.string(forKey: "jwtToken") {
                var req = URLRequest(url: url)
                req.httpMethod = "DELETE"
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                NetworkService.shared.dataTask(with: req).resume()
                
                Task { @MainActor in
                    self.serverNotifications.removeAll(where: { $0.id == serverNotifId })
                    self.buildNotifications()
                }
            }
        } else {
            // È una notifica locale, aggiungila ai clearedIds
            Task { @MainActor in
                var clearedIds = Set(UserDefaults.standard.stringArray(forKey: "clearedNotificationIds") ?? [])
                clearedIds.insert(id)
                UserDefaults.standard.set(Array(clearedIds), forKey: "clearedNotificationIds")
                self.buildNotifications()
            }
        }
    }

    /// Costruisce l'array di notifiche dai dati già scaricati.
    func buildNotifications() {
        let readIds = Set(UserDefaults.standard.stringArray(forKey: readIdsKey) ?? [])
        let clearedIds = Set(UserDefaults.standard.stringArray(forKey: "clearedNotificationIds") ?? [])
        let now = Date()
        let calendar = Calendar.current
        var result: [AppNotification] = []

        // 0. Server Notifications
        for serverNotif in serverNotifications {
            let stableId = "server_\(serverNotif.id)"
            var event: RaceEvent? = nil
            if let eId = serverNotif.eventId {
                event = events.first(where: { $0.id == eId })
            }
            let date = parseDate(from: serverNotif.createdAt) ?? now
            result.append(AppNotification(
                id: stableId,
                type: .adminAction(serverNotif: serverNotif, event: event),
                title: serverNotif.title,
                message: serverNotif.message,
                isRead: serverNotif.isRead || readIds.contains(stableId),
                timestamp: date
            ))
        }
        // Local status notifications (pending_payment, waitlist) have been removed from the Bell menu
        // so that the Bell menu acts purely as an inbox for admin notifications.
        
        // 1. Promemoria eventi imminenti (confermati, entro 7 giorni)
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
                        isRead: readIds.contains(stableId),
                        timestamp: now
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
                    isRead: readIds.contains(stableId),
                    timestamp: createdDate
                ))
            }
        }

        result = result.filter { !clearedIds.contains($0.id) }
        result.sort(by: { $0.timestamp > $1.timestamp })
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
}

nonisolated struct UserProfile: Codable, Sendable {
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
