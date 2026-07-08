import Foundation

enum AuthError: Error, LocalizedError {
    case invalidURL
    case requestFailed(String)
    case invalidCredentials
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL non valido"
        case .requestFailed(let msg): return msg
        case .invalidCredentials: return "Credenziali non valide"
        case .unknown: return "Errore sconosciuto"
        }
    }
}

struct AuthService {
    // URL di base: dinamico — segue AppEnvironment (produzione o locale)
    static var baseURL: String { AppEnvironment.shared.baseURL }

    // MARK: - Login
    static func login(username: String, password: String) async throws -> (accessToken: String, refreshToken: String) {
        guard let url = URL(string: "\(baseURL)/auth/login") else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["username": username, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode == 401 {
            throw AuthError.invalidCredentials
        } else if httpResponse.statusCode != 200 {
            let errorMsg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(errorMsg)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = json?["access_token"] as? String,
              let refresh = json?["refresh_token"] as? String else {
            throw AuthError.unknown
        }

        return (access, refresh)
    }

    // MARK: - Register
    static func register(username: String, email: String, password: String) async throws {
        guard let url = URL(string: "\(baseURL)/auth/register") else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["username": username, "email": email, "password": password]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 201 {
            let errorMsg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(errorMsg)
        }
    }

    // MARK: - Refresh Token
    static func refreshToken(_ refreshToken: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/auth/refresh") else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 200 {
            throw AuthError.requestFailed("Refresh token scaduto o invalido")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let access = json?["access_token"] as? String else {
            throw AuthError.unknown
        }

        return access
    }

    // MARK: - Logout (Server-side)
    static func logout(refreshToken: String) async {
        guard let url = URL(string: "\(baseURL)/auth/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["refresh_token": refreshToken]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        _ = try? await URLSession.shared.data(for: request) // Non ci interessa l'esito
    }

    // Helper per estrarre l'errore dalle risposte FastAPI
    private static func parseErrorMessage(data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let detail = json["detail"] as? String else {
            return "Errore imprevisto dal server"
        }
        return detail
    }

    // MARK: - Change Password
    static func changePassword(oldPassword: String, newPassword: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/auth/change-password") else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ["old_password": oldPassword, "new_password": newPassword]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 200 {
            let errorMsg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(errorMsg)
        }
    }
}

// ---------------------------------------------------------------------------
// Modello utente per la schermata admin
// ---------------------------------------------------------------------------

struct AdminUser: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String
    var role: String
    let created_at: String
}

// ---------------------------------------------------------------------------
// Estensione AuthService: chiamate API admin
// ---------------------------------------------------------------------------

extension AuthService {

    // MARK: - Fetch Users (con ricerca opzionale)
    static func fetchUsers(query: String = "", token: String) async throws -> [AdminUser] {
        var urlString = "\(baseURL)/admin/users/search"
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            urlString += "?q=\(encoded)"
        }
        guard let url = URL(string: urlString) else { throw AuthError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 200 {
            let msg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(msg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode([AdminUser].self, from: data)
    }

    // MARK: - Update User Role
    static func updateUserRole(userId: Int, role: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/admin/users/\(userId)/role") else {
            throw AuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body = ["role": role]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 200 {
            let msg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(msg)
        }
    }
}

