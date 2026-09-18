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

    var httpURL: URL? {
        var comps = URLComponents()
        comps.scheme = useTLS ? "https" : "http"
        comps.host = host
        comps.port = useTLS ? nil : port
        return comps.url
    }

    static func remoteServer(token: String) -> DiscoveredServer {
        DiscoveredServer(
            name: "Kartdromo (remoto)",
            host: "racemanager.mcarhome.duckdns.org",
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

/// Kart identity survives changes in ranking; malformed/duplicate rows get unique fallbacks.
extension TimingPayload {
    struct DisplayRow: Identifiable {
        let id: String
        let index: Int
        let values: [String]
    }

    var displayRows: [DisplayRow] {
        let kartKeywords = ["kart", "num", "n°", "no", "bib"]
        let nameKeywords = ["driver", "pilota", "name", "nome", "pilot"]
        let kartIndex = headers.firstIndex { h in kartKeywords.contains { h.lowercased().contains($0) } }
        let nameIndex = headers.firstIndex { h in nameKeywords.contains { h.lowercased().contains($0) } }
        var occurrences: [String: Int] = [:]
        return rows.enumerated().map { index, row in
            func value(at column: Int?) -> String? {
                guard let column, row.indices.contains(column) else { return nil }
                let value = row[column].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            let base: String
            if let kart = value(at: kartIndex), kart != "-" {
                base = "kart:\(kart)"
            } else if let name = value(at: nameIndex) {
                base = "driver:\(name)"
            } else {
                base = "row:\(index)"
            }
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return DisplayRow(id: "\(base):\(occurrence)", index: index, values: row)
        }
    }
}
