import Foundation

// ---------------------------------------------------------------------------
// Ruoli utente
// ---------------------------------------------------------------------------

enum UserRole: String, Codable {
    case viewer       = "viewer"
    case raceDirector = "race_director"
    case admin        = "admin"

    /// Può cambiare l'URL della sorgente dati (comandare lo scraping)
    var canChangeURL: Bool {
        self == .raceDirector || self == .admin
    }

    /// Può gestire utenti e configurazione del server
    var canManageUsers: Bool {
        self == .admin
    }

    /// Nome leggibile da mostrare in UI
    var displayName: String {
        switch self {
        case .viewer:       return "Spettatore"
        case .raceDirector: return "Direttore di gara"
        case .admin:        return "Admin"
        }
    }
}

// ---------------------------------------------------------------------------
// Utente autenticato (dati estratti dal JWT)
// ---------------------------------------------------------------------------

struct LoggedInUser {
    let id: Int
    let role: UserRole
}

// ---------------------------------------------------------------------------
// Decodifica JWT lato client (senza verifica firma)
//
// Usata SOLO per personalizzare la UI in base al ruolo.
// La vera verifica della firma avviene sempre lato server.
// ---------------------------------------------------------------------------

func decodeJWT(_ token: String) -> LoggedInUser? {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { return nil }

    // Base64url → base64 standard
    var payload = String(parts[1])
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    // Padding a multiplo di 4
    while payload.count % 4 != 0 { payload += "=" }

    guard
        let data    = Data(base64Encoded: payload),
        let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let sub     = json["sub"]  as? String,
        let userId  = Int(sub),
        let roleStr = json["role"] as? String,
        let role    = UserRole(rawValue: roleStr)
    else { return nil }

    return LoggedInUser(id: userId, role: role)
}
