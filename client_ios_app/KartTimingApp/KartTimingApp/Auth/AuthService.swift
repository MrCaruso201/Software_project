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

        let (data, response) = try await NetworkService.shared.data(for: request)
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

        let (data, response) = try await NetworkService.shared.data(for: request)
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

        let (data, response) = try await NetworkService.shared.data(for: request)
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

        _ = try? await NetworkService.shared.data(for: request) // Non ci interessa l'esito
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

        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 200 {
            let errorMsg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(errorMsg)
        }
    }
    
    // MARK: - Update Profile
    static func updateProfile(firstName: String, lastName: String, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/auth/me") else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let body: [String: String?] = [
            "first_name": firstName.isEmpty ? nil : firstName,
            "last_name": lastName.isEmpty ? nil : lastName
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 200 {
            let errorMsg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(errorMsg)
        }
    }
    
    // MARK: - Delete Account
    static func deleteAccount(token: String) async throws {
        guard let url = URL(string: "\(baseURL)/auth/me") else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 204 {
            let errorMsg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(errorMsg)
        }
    }
    
    // MARK: - Upload Avatar
    static func uploadAvatar(imageData: Data, token: String) async throws {
        guard let url = URL(string: "\(baseURL)/auth/me/avatar") else { throw AuthError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await NetworkService.shared.data(for: request)
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
    let profilePictureUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, username, email, role, created_at
        case profilePictureUrl = "profile_picture_url"
    }
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

        let (data, response) = try await NetworkService.shared.data(for: request)
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

        let (data, response) = try await NetworkService.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw AuthError.unknown }

        if httpResponse.statusCode != 200 {
            let msg = parseErrorMessage(data: data)
            throw AuthError.requestFailed(msg)
        }
    }
}

