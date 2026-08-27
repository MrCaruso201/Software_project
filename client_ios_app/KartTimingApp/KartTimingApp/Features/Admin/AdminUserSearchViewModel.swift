import Foundation
import Combine

class AdminUserSearchViewModel: ObservableObject {
    @Published var searchResults: [UserProfile] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    // Per gestire il debounce della ricerca
    private var cancellables = Set<AnyCancellable>()
    @Published var searchQuery: String = ""
    
    // Server & Auth references
    private var serverURL: URL?
    private var token: String?
    
    // Per il dettaglio utente
    @Published var userRegistrations: [EventRegistrationResponse] = []
    @Published var allEvents: [RaceEvent] = []
    
    init(serverURL: URL? = nil, token: String? = nil) {
        self.serverURL = serverURL
        self.token = token
        
        $searchQuery
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.searchUsers(query: query)
            }
            .store(in: &cancellables)
    }
    
    func setup(serverURL: URL?, token: String?) {
        self.serverURL = serverURL
        self.token = token
    }
    
    private func searchUsers(query: String) {
        guard let serverURL = serverURL, let token = token else { return }
        
        // Se la query è vuota, potremmo voler pulire o mostrare tutti gli utenti
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let url = serverURL.appendingPathComponent("admin/users/search").absoluteString + "?q=\(encodedQuery)"
        guard let finalURL = URL(string: url) else { return }
        
        var request = URLRequest(url: finalURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        isLoading = true
        errorMessage = nil
        
        NetworkService.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                guard let data = data else { return }
                
                do {
                    let users = try JSONDecoder().decode([UserProfile].self, from: data)
                    self.searchResults = users.filter { !["admin", "race_director", "viewer"].contains($0.role) }
                } catch {
                    self.errorMessage = "Errore di decodifica: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    func fetchUserDetails(targetUserId: Int) {
        guard let serverURL = serverURL, let token = token else { return }
        
        isLoading = true
        errorMessage = nil
        
        let group = DispatchGroup()
        
        // Fetch tutti gli eventi (per recuperare data, luogo, ecc)
        group.enter()
        let eventsURL = serverURL.appendingPathComponent("events/")
        var reqEvents = URLRequest(url: eventsURL)
        reqEvents.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: reqEvents) { data, _, _ in
            if let data = data, let events = try? JSONDecoder().decode([RaceEvent].self, from: data) {
                DispatchQueue.main.async { self.allEvents = events }
            }
            group.leave()
        }.resume()
        
        // Fetch iscrizioni dell'utente
        group.enter()
        let regsURL = serverURL.appendingPathComponent("events/registrations/user/\(targetUserId)")
        var reqRegs = URLRequest(url: regsURL)
        reqRegs.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: reqRegs) { data, response, _ in
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200,
               let data = data, let regs = try? JSONDecoder().decode([EventRegistrationResponse].self, from: data) {
                DispatchQueue.main.async { self.userRegistrations = regs }
            } else {
                DispatchQueue.main.async { self.userRegistrations = [] }
            }
            group.leave()
        }.resume()
        
        group.notify(queue: .main) {
            self.isLoading = false
        }
    }
}
