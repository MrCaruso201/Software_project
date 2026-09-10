import Foundation

actor NetworkService {
    static let shared = NetworkService()
    
    private struct CacheKey: Hashable {
        let url: URL?
        let headers: [String: String]
    }
    private struct CacheEntry {
        let data: Data
        let response: URLResponse
        let expires: Date
    }
    private var cache: [CacheKey: CacheEntry] = [:]
    private var pending: [CacheKey: (id: UUID, task: Task<(Data, URLResponse), Error>)] = [:]
    private var cacheGeneration = UUID()

    private func invalidateCache() {
        cache.removeAll()
        pending.removeAll()
        cacheGeneration = UUID()
    }

    /// Opt-in short-lived cache. Authorization and host are part of the key.
    func cachedData(for request: URLRequest, lifetime: TimeInterval, forceRefresh: Bool) async throws -> (Data, URLResponse) {
        guard lifetime > 0, (request.httpMethod ?? "GET") == "GET" else { return try await data(for: request) }
        let key = CacheKey(url: request.url, headers: request.allHTTPHeaderFields ?? [:])
        if forceRefresh { cache[key] = nil; pending[key] = nil }
        cache = cache.filter { $0.value.expires > Date() }
        if let hit = cache[key] { return (hit.data, hit.response) }
        if let existing = pending[key] { return try await existing.task.value }
        let generation = cacheGeneration
        let id = UUID()
        let task = Task { try await self.data(for: request) }
        pending[key] = (id, task)
        defer { if pending[key]?.id == id { pending[key] = nil } }
        let (data, response) = try await task.value
        if generation == cacheGeneration, pending[key]?.id == id, let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) {
            if cache.count >= 32 { cache.removeAll() }
            cache[key] = CacheEntry(data: data, response: response, expires: Date().addingTimeInterval(lifetime))
        }
        return (data, response)
    }

    private var isRefreshing = false
    private var refreshTask: Task<String?, Never>?
    
    /// Effettua una richiesta di rete con supporto al retry automatico in caso di 401
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let isMutation = !["GET", "HEAD"].contains(request.httpMethod ?? "GET")
        if isMutation { invalidateCache() }
        defer { if isMutation { invalidateCache() } }
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
    nonisolated func dataTask(with request: URLRequest, cacheFor: TimeInterval = 0, forceRefresh: Bool = false, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> NetworkTask {
        Task {
            do {
                let (data, response) = try await self.cachedData(for: request, lifetime: cacheFor, forceRefresh: forceRefresh)
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
