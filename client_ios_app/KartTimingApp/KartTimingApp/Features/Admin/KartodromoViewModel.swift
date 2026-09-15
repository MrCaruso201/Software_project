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

        NetworkService.shared.dataTask(with: request) { data, response, error in
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

    // MARK: - Fetch Active (GET /kartodromi/ — viewers)

    func fetchActive(serverURL: URL?, token: String?) {
        guard let serverURL = serverURL else {
            errorMessage = "Nessun server disponibile"
            return
        }
        let url = serverURL.appendingPathComponent("kartodromi/")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        isLoading = true
        errorMessage = nil

        NetworkService.shared.dataTask(with: request) { data, response, error in
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

        NetworkService.shared.dataTask(with: request) { _, response, _ in
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
        errorMessage = nil
        guard let serverURL = serverURL else {
            errorMessage = "Nessun server disponibile"
            completion(false)
            return
        }
        let url = serverURL.appendingPathComponent("kartodromi/\(kartodromoId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        guard let body = try? JSONSerialization.data(withJSONObject: data) else { completion(false); return }
        request.httpBody = body

        NetworkService.shared.dataTask(with: request) { responseData, response, error in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.fetchAll(serverURL: serverURL, token: token)
                    completion(true)
                } else {
                    let payload = responseData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                    self.errorMessage = payload?["detail"] as? String
                        ?? error?.localizedDescription
                        ?? "Errore durante il salvataggio."
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

        NetworkService.shared.dataTask(with: request) { _, response, _ in
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

    // MARK: - Upload Image (POST /kartodromi/{id}/image)

    func uploadImage(
        serverURL: URL?,
        kartodromoId: Int,
        imageData: Data,
        fileName: String,
        mimeType: String,
        token: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard let serverURL = serverURL else { completion(false); return }
        let url = serverURL.appendingPathComponent("kartodromi/\(kartodromoId)/image")

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()
        let crlf = "\r\n"
        body.append("--\(boundary)\(crlf)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(crlf)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(crlf)\(crlf)".data(using: .utf8)!)
        body.append(imageData)
        body.append("\(crlf)--\(boundary)--\(crlf)".data(using: .utf8)!)
        request.httpBody = body

        NetworkService.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    self.fetchAll(serverURL: serverURL, token: token)
                    completion(true)
                } else {
                    completion(false)
                }
            }
        }.resume()
    }
}
