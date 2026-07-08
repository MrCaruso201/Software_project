import Foundation
import Combine

class KartodromoViewModel: ObservableObject {
    @Published var kartodromi: [Kartodromo] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Fetch (GET /kartodromi/tutti — admin)

    func fetchAll(serverURL: URL?, token: String?) {
        guard let serverURL = serverURL else {
            errorMessage = "Nessun server disponibile"
            return
        }
        let url = serverURL.appendingPathComponent("kartodromi/tutti")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

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
                    let decoder = JSONDecoder()
                    self.kartodromi = try decoder.decode([Kartodromo].self, from: data)
                } catch {
                    self.errorMessage = "Errore di decodifica."
                }
            }
        }.resume()
    }

    // MARK: - Create (POST /kartodromi/)

    func create(serverURL: URL?, data: [String: Any], token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL else { completion(false); return }
        let url = serverURL.appendingPathComponent("kartodromi/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let body = try? JSONSerialization.data(withJSONObject: data) else { completion(false); return }
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 201 {
                    self.fetchAll(serverURL: serverURL, token: token)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    // MARK: - Update (PATCH /kartodromi/{id})

    func update(serverURL: URL?, kartodromoId: Int, data: [String: Any], token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL else { completion(false); return }
        let url = serverURL.appendingPathComponent("kartodromi/\(kartodromoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let body = try? JSONSerialization.data(withJSONObject: data) else { completion(false); return }
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.fetchAll(serverURL: serverURL, token: token)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }

    // MARK: - Delete (DELETE /kartodromi/{id})

    func delete(serverURL: URL?, kartodromoId: Int, token: String?, completion: @escaping (Bool) -> Void) {
        guard let serverURL = serverURL else { completion(false); return }
        let url = serverURL.appendingPathComponent("kartodromi/\(kartodromoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 204 {
                    self.fetchAll(serverURL: serverURL, token: token)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
}
