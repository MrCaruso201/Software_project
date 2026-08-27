import Foundation
import Combine

class EventiViewModel: ObservableObject {
    @Published var events: [RaceEvent] = []
    @Published var userRegistrations: [Int: EventRegistrationResponse] = [:]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    func fetchEvents(serverURL: URL?, completion: (() -> Void)? = nil) {
        guard let serverURL = serverURL else {
            self.errorMessage = "Nessun server disponibile"
            return
        }
        
        let url = serverURL.appendingPathComponent("events/")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        isLoading = true
        errorMessage = nil
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                defer { completion?() }
                
                if let error = error {
                    self.errorMessage = "Errore di rete: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "Nessun dato ricevuto"
                    return
                }
                
                do {
                    let decodedEvents = try JSONDecoder().decode([RaceEvent].self, from: data)
                    self.events = decodedEvents
                } catch {
                    self.errorMessage = "Errore di decodifica dei dati."
                }
            }
        }.resume()
    }
    
    func createEvent(serverURL: URL?, eventData: [String: Any], token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData, options: [])
        } catch {
            completion(false)
            return
        }
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 201 {
                    self.fetchEvents(serverURL: serverURL)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func updateEvent(serverURL: URL?, eventId: Int, eventData: [String: Any], token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: eventData, options: [])
        } catch {
            completion(false)
            return
        }
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    self.fetchEvents(serverURL: serverURL)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func deleteEvent(serverURL: URL?, eventId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, (httpRes.statusCode == 200 || httpRes.statusCode == 204) {
                    self.events.removeAll { $0.id == eventId }
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    // MARK: - Registration Methods
    
    func fetchUserRegistrations(serverURL: URL?, token: String?) {
        guard let serverURL = serverURL, let token = token else { return }
        
        let url = serverURL.appendingPathComponent("events/registrations/me")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else { return }
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    do {
                        let regs = try JSONDecoder().decode([EventRegistrationResponse].self, from: data)
                        var newDict = [Int: EventRegistrationResponse]()
                        for r in regs {
                            newDict[r.eventId] = r
                        }
                        self.userRegistrations = newDict
                    } catch {
                        print("Errore decodifica registrazioni:", error)
                    }
                }
            }
        }.resume()
    }
    
    func registerToEvent(
        serverURL: URL?,
        eventId: Int,
        token: String?,
        teamName: String? = nil,
        memberEmails: [String]? = nil,
        acceptsExtraPilots: Bool? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let serverURL = serverURL, let token = token else {
            completion(false, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Se si tratta di una gara a squadre, invia il body JSON
        if let teamName = teamName {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = [
                "team_name": teamName,
                "member_emails": memberEmails ?? []
            ]
            if let accepts = acceptsExtraPilots {
                body["accepts_extra_pilots"] = accepts
            }
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        }
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse {
                    if httpRes.statusCode == 201 {
                        if let data = data, let reg = try? JSONDecoder().decode(EventRegistrationResponse.self, from: data) {
                            self.userRegistrations[eventId] = reg
                        }
                        completion(true, nil)
                    } else {
                        var msg = "Errore durante l'iscrizione"
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                            msg = detail
                        }
                        completion(false, msg)
                    }
                } else {
                    completion(false, "Risposta non valida dal server")
                }
            }
        }.resume()
    }
    
    func adminRegisterIndividual(
        serverURL: URL?,
        eventId: Int,
        token: String?,
        email: String,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let serverURL = serverURL, let token = token else {
            completion(false, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/admin_register/individual")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "email": email
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                if let httpRes = response as? HTTPURLResponse {
                    if httpRes.statusCode == 201 || httpRes.statusCode == 200 {
                        completion(true, nil)
                    } else {
                        var msg = "Errore durante l'iscrizione manuale"
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                            msg = detail
                        }
                        completion(false, msg)
                    }
                } else {
                    completion(false, "Risposta non valida dal server")
                }
            }
        }.resume()
    }

    func adminRegisterTeam(
        serverURL: URL?,
        eventId: Int,
        token: String?,
        teamName: String,
        leaderEmail: String,
        memberEmails: [String],
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let serverURL = serverURL, let token = token else {
            completion(false, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/admin_register/team")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "team_name": teamName,
            "leader_email": leaderEmail,
            "member_emails": memberEmails
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                if let httpRes = response as? HTTPURLResponse {
                    if httpRes.statusCode == 201 || httpRes.statusCode == 200 {
                        completion(true, nil)
                    } else {
                        var msg = "Errore durante l'iscrizione manuale"
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                            msg = detail
                        }
                        completion(false, msg)
                    }
                } else {
                    completion(false, "Risposta non valida dal server")
                }
            }
        }.resume()
    }
    
    func unregisterFromEvent(serverURL: URL?, eventId: Int, token: String?, completion: @escaping (Bool, String?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/register")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse, (httpRes.statusCode == 200 || httpRes.statusCode == 204) {
                    self.userRegistrations.removeValue(forKey: eventId)
                    completion(true, nil)
                } else {
                    var msg = "Errore durante l'annullamento"
                    if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                        msg = detail
                    }
                    completion(false, msg)
                }
            }
        }.resume()
    }
    
    func updateTeamRegistration(
        serverURL: URL?,
        eventId: Int,
        teamId: String,
        token: String?,
        teamName: String,
        memberEmails: [String],
        leaderEmail: String? = nil,
        acceptsExtraPilots: Bool? = nil,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let serverURL = serverURL, let token = token else {
            completion(false, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/team/\(teamId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "team_name": teamName,
            "member_emails": memberEmails
        ]
        
        if let leader = leaderEmail {
            body["leader_email"] = leader
        }
        if let accepts = acceptsExtraPilots {
            body["accepts_extra_pilots"] = accepts
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse {
                    if httpRes.statusCode == 200 {
                        if let data = data, let reg = try? JSONDecoder().decode(EventRegistrationResponse.self, from: data) {
                            self.userRegistrations[eventId] = reg
                        }
                        completion(true, nil)
                    } else {
                        var msg = "Errore durante l'aggiornamento"
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                            msg = detail
                        }
                        completion(false, msg)
                    }
                } else {
                    completion(false, "Risposta non valida dal server")
                }
            }
        }.resume()
    }
    
    // MARK: - Admin Registration Methods
    
    func fetchEventRegistrations(serverURL: URL?, eventId: Int, token: String?, completion: @escaping ([EventRegistrationWithUserResponse]?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(nil)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    completion(nil)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    let regs = try? JSONDecoder().decode([EventRegistrationWithUserResponse].self, from: data)
                    completion(regs)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
    
    // MARK: - Admin: Unassigned Registrations
    
    func fetchUnassignedRegistrations(serverURL: URL?, eventId: Int, token: String?, completion: @escaping ([EventRegistrationWithUserResponse]?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(nil)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/admin_register/unassigned")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error fetching unassigned regs: \(error)")
                    completion(nil)
                    return
                }
                
                if let data = data, let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    let decoder = JSONDecoder()
                    let regs = try? decoder.decode([EventRegistrationWithUserResponse].self, from: data)
                    completion(regs)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
    
    // MARK: - Admin: Teams
    
    func fetchTeamRegistrations(serverURL: URL?, eventId: Int, token: String?, completion: @escaping ([TeamRegistrationResponse]?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(nil)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/teams")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    completion(nil)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    let decoder = JSONDecoder()
                    let teams = try? decoder.decode([TeamRegistrationResponse].self, from: data)
                    completion(teams)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
    
    func adminConfirmIndividualRegistration(serverURL: URL?, eventId: Int, registrationId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/\(registrationId)/confirm")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminUnconfirmIndividualRegistration(serverURL: URL?, eventId: Int, registrationId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/\(registrationId)/unconfirm")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    func adminDeleteIndividualRegistration(serverURL: URL?, eventId: Int, registrationId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/\(registrationId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, (httpRes.statusCode == 200 || httpRes.statusCode == 204) {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminAssignToTeam(serverURL: URL?, eventId: Int, teamId: String, registrationIds: [Int], token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/admin_register/teams/\(teamId)/assign")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "registration_ids": registrationIds
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error assigning team: \(error)")
                    completion(false)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminCreateTeamFromIndividuals(serverURL: URL?, eventId: Int, teamName: String, leaderId: Int, memberIds: [Int], acceptsExtraPilots: Bool, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/admin_register/teams/create_from_individuals")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "team_name": teamName,
            "leader_registration_id": leaderId,
            "member_registration_ids": memberIds,
            "accepts_extra_pilots": acceptsExtraPilots
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error creating team from individuals: \(error)")
                    completion(false)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 || httpRes.statusCode == 201 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    // MARK: - Team Admin Methods
    
    func adminConfirmTeamRegistration(serverURL: URL?, eventId: Int, teamId: String, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/team/\(teamId)/confirm")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminUnconfirmTeamRegistration(serverURL: URL?, eventId: Int, teamId: String, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/team/\(teamId)/unconfirm")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminDeleteTeamRegistration(serverURL: URL?, eventId: Int, teamId: String, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/team/\(teamId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, (httpRes.statusCode == 200 || httpRes.statusCode == 204) {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    func adminAcceptWaitlistRegistration(serverURL: URL?, eventId: Int, registrationId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/\(registrationId)/accept_waitlist")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminAcceptWaitlistTeamRegistration(serverURL: URL?, eventId: Int, teamId: String, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/team/\(teamId)/accept_waitlist")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminMoveToWaitlistRegistration(serverURL: URL?, eventId: Int, registrationId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/\(registrationId)/move_to_waitlist")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func adminMoveToWaitlistTeamRegistration(serverURL: URL?, eventId: Int, teamId: String, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/team/\(teamId)/move_to_waitlist")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    // MARK: - Leave Team (non-leader)

    /// Permette a un membro NON-leader di abbandonare il team.
    /// Rimuove solo la propria iscrizione; il resto del team rimane invariato.
    /// Funziona anche con status "confirmed".
    func leaveTeam(
        serverURL: URL?,
        eventId: Int,
        token: String?,
        completion: @escaping (Bool, String?) -> Void
    ) {
        guard let serverURL = serverURL, let token = token else {
            completion(false, "Parametri mancanti")
            return
        }

        let url = serverURL.appendingPathComponent("events/\(eventId)/registrations/me/leave")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                if let httpRes = response as? HTTPURLResponse,
                   httpRes.statusCode == 204 || httpRes.statusCode == 200 {
                    self.userRegistrations.removeValue(forKey: eventId)
                    completion(true, nil)
                } else {
                    var msg = "Errore durante l'abbandono del team"
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let detail = json["detail"] as? String {
                        msg = detail
                    }
                    completion(false, msg)
                }
            }
        }.resume()
    }
    
    // MARK: - Release Forms
    
    func fetchReleaseFormText(serverURL: URL?, eventId: Int, completion: @escaping (String?) -> Void) {
        guard let serverURL = serverURL else {
            completion(nil)
            return
        }
        let url = serverURL.appendingPathComponent("events/\(eventId)/release-form")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    completion(nil)
                    return
                }
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let text = json["release_form_text"] as? String {
                    completion(text)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
    
    func signReleaseForm(serverURL: URL?, eventId: Int, token: String?, firstName: String, lastName: String, codiceFiscale: String, birthDate: String, residence: String, signatureBase64: String, completion: @escaping (Bool, String?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/release-form/sign")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "first_name": firstName,
            "last_name": lastName,
            "codice_fiscale": codiceFiscale,
            "birth_date": birthDate,
            "residence": residence,
            "signature_base64": signatureBase64
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                    return
                }
                if let httpRes = response as? HTTPURLResponse {
                    if httpRes.statusCode == 200 {
                        completion(true, nil)
                    } else {
                        var msg = "Errore durante l'invio della firma"
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                            msg = detail
                        }
                        completion(false, msg)
                    }
                } else {
                    completion(false, "Risposta non valida")
                }
            }
        }.resume()
    }
    
    func fetchMyReleaseForm(serverURL: URL?, eventId: Int, token: String?, completion: @escaping (SignedReleaseResponse?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(nil)
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/release-form/mine")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let data = data, let decoded = try? JSONDecoder().decode(SignedReleaseResponse.self, from: data) {
                    completion(decoded)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
    
    func previewUserReleaseForm(serverURL: URL?, eventId: Int, token: String?, firstName: String, lastName: String, codiceFiscale: String, birthDate: String, residence: String, signatureBase64: String, completion: @escaping (Data?, String?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(nil, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("events/\(eventId)/release-form/preview")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "first_name": firstName,
            "last_name": lastName,
            "codice_fiscale": codiceFiscale,
            "birth_date": birthDate,
            "residence": residence,
            "signature_base64": signatureBase64
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(nil, error.localizedDescription)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse {
                    if httpRes.statusCode == 200, let data = data {
                        completion(data, nil)
                    } else {
                        var msg = "Errore durante l'anteprima"
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                            msg = detail
                        }
                        completion(nil, msg)
                    }
                } else {
                    completion(nil, "Risposta non valida")
                }
            }
        }.resume()
    }
    
    // MARK: - Admin Release Forms
    
    func adminUpdateReleaseForm(serverURL: URL?, eventId: Int, token: String?, text: String, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        let url = serverURL.appendingPathComponent("admin/events/\(eventId)/release-form")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["release_form_text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
    
    func previewAdminReleaseForm(serverURL: URL?, eventId: Int, token: String?, text: String, completion: @escaping (Data?, String?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(nil, "Parametri mancanti")
            return
        }
        
        let url = serverURL.appendingPathComponent("admin/events/\(eventId)/release-form/preview")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "release_form_text": text
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(nil, error.localizedDescription)
                    return
                }
                
                if let httpRes = response as? HTTPURLResponse {
                    if httpRes.statusCode == 200, let data = data {
                        completion(data, nil)
                    } else {
                        var msg = "Errore durante l'anteprima"
                        if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let detail = json["detail"] as? String {
                            msg = detail
                        }
                        completion(nil, msg)
                    }
                } else {
                    completion(nil, "Risposta non valida")
                }
            }
        }.resume()
    }
    
    func adminFetchSignedReleases(serverURL: URL?, eventId: Int, token: String?, completion: @escaping ([SignedReleaseResponse]?) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(nil)
            return
        }
        let url = serverURL.appendingPathComponent("admin/events/\(eventId)/releases")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data, error == nil else {
                    completion(nil)
                    return
                }
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    let decoded = try? JSONDecoder().decode([SignedReleaseResponse].self, from: data)
                    completion(decoded)
                } else {
                    completion(nil)
                }
            }
        }.resume()
    }
    
    func adminDeleteSignedRelease(serverURL: URL?, eventId: Int, userId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL, let token = token else {
            completion(false)
            return
        }
        let url = serverURL.appendingPathComponent("admin/events/\(eventId)/releases/\(userId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
}

