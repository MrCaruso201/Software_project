import Foundation

actor NetworkService {
    static let shared = NetworkService()
    
    private var isRefreshing = false
    private var refreshTask: Task<String?, Never>?
    
    /// Effettua una richiesta di rete con supporto al retry automatico in caso di 401
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var req = request
        let (data, response) = try await URLSession.shared.data(for: req)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            // Se la richiesta originale era per il login, register o refresh, non intercettiamo
            if let urlString = req.url?.absoluteString, 
               urlString.contains("/auth/login") || urlString.contains("/auth/register") || urlString.contains("/auth/refresh") {
                return (data, response)
            }
            
            // Prova a fare il refresh del token
            if let newToken = await refreshToken() {
                // Aggiorna l'header di autorizzazione con il nuovo token
                req.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                // Riporva la richiesta
                return try await URLSession.shared.data(for: req)
            }
        }
        
        return (data, response)
    }
    
    class NetworkTask {
        func resume() {}
    }
    
    /// Versione con completion handler per compatibilità con il codice legacy
    @discardableResult
    nonisolated func dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> NetworkTask {
        Task {
            do {
                let (data, response) = try await self.data(for: request)
                completionHandler(data, response, nil)
            } catch {
                completionHandler(nil, nil, error)
            }
        }
        return NetworkTask()
    }
    
    @discardableResult
    nonisolated func dataTask(with request: URLRequest) -> NetworkTask {
        return dataTask(with: request, completionHandler: { _, _, _ in })
    }
    
    private func refreshToken() async -> String? {
        if isRefreshing {
            if let task = refreshTask {
                return await task.value
            }
            return nil
        }
        
        isRefreshing = true
        refreshTask = Task { @MainActor in
            let newToken = await AuthState.shared.handleTokenExpiryWithReturn()
            return newToken
        }
        
        let result = await refreshTask?.value
        isRefreshing = false
        refreshTask = nil
        
        return result
    }
}

/// Runs JSON decoding on the concurrent executor, regardless of the caller's actor.
nonisolated enum BackgroundJSON {
    @concurrent
    static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) async throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
