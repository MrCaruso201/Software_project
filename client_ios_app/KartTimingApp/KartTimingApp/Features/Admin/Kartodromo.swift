import Foundation

// MARK: - Modello

struct Kartodromo: Identifiable, Hashable, Codable {
    let id: Int
    let nome: String
    let luogo: String
    let url: String
    let sitoWeb: String
    let imageUrl: String?
    let attivo: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, nome, luogo, url, attivo
        case sitoWeb   = "sito_web"
        case imageUrl  = "image_url"
        case createdAt = "created_at"
    }
}

// MARK: - Service (fetch pubblico — viewer)

enum KartodromoServiceError: LocalizedError {
    case tokenMancante
    case rispostaInvalida
    case serverError(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .tokenMancante:
            return "Sessione non autenticata. Effettuare il login."
        case .rispostaInvalida:
            return "Risposta del server non valida."
        case .serverError(let code):
            return "Errore dal server (codice \(code))."
        case .networkError(let e):
            return "Errore di rete: \(e.localizedDescription)"
        }
    }
}

/// Recupera la lista dei kartodromi attivi dal server.
struct KartodromoService {

    /// Scarica i kartodromi attivi da `GET {baseURL}/kartodromi/`.
    ///
    /// - Parameters:
    ///   - baseURL: Base URL del server (es. `"https://marcos-macbook-pro.tail71e118.ts.net"`).
    ///   - accessToken: JWT access token (ruolo minimo: viewer).
    /// - Returns: Array di `Kartodromo` restituiti dal server.
    static func fetchKartodromi(baseURL: String, accessToken: String) async throws -> [Kartodromo] {
        guard let url = URL(string: "\(baseURL)/kartodromi/") else {
            throw KartodromoServiceError.rispostaInvalida
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw KartodromoServiceError.networkError(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KartodromoServiceError.serverError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode([Kartodromo].self, from: data)
        } catch {
            throw KartodromoServiceError.rispostaInvalida
        }
    }
}
