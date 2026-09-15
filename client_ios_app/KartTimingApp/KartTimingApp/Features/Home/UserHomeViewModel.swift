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

    @Published var notificationError: String?
    private var notificationScope: String { "\(currentServerURL?.absoluteString ?? "")_\(profile?.id ?? 0)" }
    private var readIdsKey: String { "readNotificationIds_\(notificationScope)" }
    private var clearedIdsKey: String { "clearedNotificationIds_\(notificationScope)" }

    // MARK: - Statistiche calcolate

    var totalRegistrations: Int { registrations.count }
    var confirmedRegistrations: Int { registrations.filter { $0.status == "confirmed" }.count }
    var pendingRegistrations: Int { registrations.filter { $0.status == "pending_payment" }.count }
    var waitlistRegistrations: Int { registrations.filter { $0.status == "waitlist" }.count }

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    // MARK: - Fetch

    func fetchData(serverURL: URL?, token: String?, forceRefresh: Bool = false, completion: (() -> Void)? = nil) {
        guard let serverURL = serverURL, let token = token else {
            Task { @MainActor in self.isLoading = false; completion?() }
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
        NetworkService.shared.dataTask(with: reqNotif) { data, _, _ in
            Task { @MainActor in
                if let data = data, let notifs = try? await BackgroundJSON.decode([ServerNotification].self, from: data) {
                    self.serverNotifications = notifs
                    self.notificationError = nil
                } else {
                    self.notificationError = "Impossibile aggiornare le notifiche. Riprova."
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

    func refreshNotifications() {
        fetchData(serverURL: currentServerURL, token: currentToken, forceRefresh: true)
    }

    private func mutateNotification(path: String, method: String, onSuccess: @escaping () -> Void) {
        guard let url = currentServerURL, let token = currentToken else {
            notificationError = "Sessione non disponibile. Accedi nuovamente."
            return
        }
        var request = URLRequest(url: url.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        NetworkService.shared.dataTask(with: request) { _, response, error in
            Task { @MainActor in
                guard error == nil, let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode) else {
                    self.notificationError = "Impossibile salvare la modifica alle notifiche. Riprova."
                    return
                }
                self.notificationError = nil
                onSuccess()
            }
        }.resume()
    }

    func deleteAllNotifications() {
        let localIds = notifications.filter { !$0.id.hasPrefix("server_") }.map(\.id)
        mutateNotification(path: "notifications/me", method: "DELETE") {
            var clearedIds = Set(UserDefaults.standard.stringArray(forKey: self.clearedIdsKey) ?? [])
            clearedIds.formUnion(localIds)
            UserDefaults.standard.set(Array(clearedIds), forKey: self.clearedIdsKey)
            self.serverNotifications.removeAll()
            self.buildNotifications()
        }
    }

    func markNotificationRead(id: String) {
        if id.hasPrefix("server_"), let serverId = Int(id.dropFirst(7)) {
            mutateNotification(path: "notifications/\(serverId)/read", method: "POST") {
                if let index = self.serverNotifications.firstIndex(where: { $0.id == serverId }) {
                    self.serverNotifications[index].isRead = true
                }
                self.buildNotifications()
            }
        } else {
            var readIds = Set(UserDefaults.standard.stringArray(forKey: readIdsKey) ?? [])
            readIds.insert(id)
            UserDefaults.standard.set(Array(readIds), forKey: readIdsKey)
            buildNotifications()
        }
    }

    func deleteSingleNotification(id: String) {
        if id.hasPrefix("server_"), let serverId = Int(id.dropFirst(7)) {
            mutateNotification(path: "notifications/\(serverId)", method: "DELETE") {
                self.serverNotifications.removeAll { $0.id == serverId }
                self.buildNotifications()
            }
        } else {
            var clearedIds = Set(UserDefaults.standard.stringArray(forKey: clearedIdsKey) ?? [])
            clearedIds.insert(id)
            UserDefaults.standard.set(Array(clearedIds), forKey: clearedIdsKey)
            buildNotifications()
        }
    }

    /// Costruisce l'array di notifiche dai dati già scaricati.
    func buildNotifications() {
        let clearedIds = Set(UserDefaults.standard.stringArray(forKey: clearedIdsKey) ?? [])
        let now = Date()
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
                isRead: serverNotif.isRead,
                timestamp: date
            ))
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
