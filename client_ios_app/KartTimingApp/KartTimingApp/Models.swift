import Foundation

struct TimingPayload {
    let updatedAt: String
    let headers: [String]
    let rows: [[String]]
    let url: String
}

struct DiscoveredServer: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int
    var useTLS: Bool = false
    var token: String? = nil

    var wsURL: URL? {
        var comps = URLComponents()
        comps.scheme = useTLS ? "wss" : "ws"
        comps.host = host
        comps.port = useTLS ? nil : port
        comps.path = "/ws"
        if let token {
            comps.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        return comps.url
    }

    static func remoteServer(token: String) -> DiscoveredServer {
        DiscoveredServer(
            name: "Kartdromo (remoto)",
            host: "marcos-macbook-pro.tail71e118.ts.net",
            port: 443,
            useTLS: true,
            token: token
        )
    }

    /// Server locale — usato in DEV MODE (Bonjour/mDNS, senza TLS)
    static func localServer(token: String) -> DiscoveredServer {
        DiscoveredServer(
            name: "Kartdromo (locale)",
            host: AppEnvironment.shared.selectedLocalHost ?? "localhost",
            port: AppEnvironment.shared.selectedLocalPort ?? 8000,
            useTLS: false,
            token: token
        )
    }
}
