import Foundation
import Combine

class UserHomeViewModel: ObservableObject {
    @Published var profile: UserProfile?
    @Published var registrations: [EventRegistrationResponse] = []
    @Published var events: [RaceEvent] = []
    
    @Published var isLoading = true
    
    // Statistiche calcolate
    var totalRegistrations: Int { registrations.count }
    var confirmedRegistrations: Int { registrations.filter { $0.status == "confirmed" }.count }
    var pendingRegistrations: Int { registrations.filter { $0.status == "pending_payment" }.count }
    
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
        }
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
