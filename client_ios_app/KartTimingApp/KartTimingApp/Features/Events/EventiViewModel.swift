import Foundation
import Combine

class EventiViewModel: ObservableObject {
    @Published var events: [RaceEvent] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    func fetchEvents(serverURL: URL?) {
        guard let serverURL = serverURL else {
            self.errorMessage = "Nessun server disponibile"
            return
        }
        
        let url = serverURL.appendingPathComponent("events/")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        isLoading = true
        errorMessage = nil
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
        
        URLSession.shared.dataTask(with: request) { data, response, error in
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
}
