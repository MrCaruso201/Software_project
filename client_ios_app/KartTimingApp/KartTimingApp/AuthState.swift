import Foundation
import Combine

@MainActor
class AuthState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: LoggedInUser? = nil

    static let shared = AuthState()

    init() {
        // Al lancio, verifica se c'è un token salvato nel Keychain
        if let token = KeychainService.load(key: "access_token"),
           let user = decodeJWT(token) {
            self.currentUser = user
            self.isLoggedIn = true
        }
    }

    func setLoginData(accessToken: String, refreshToken: String) {
        KeychainService.save(key: "access_token", value: accessToken)
        KeychainService.save(key: "refresh_token", value: refreshToken)
        if let user = decodeJWT(accessToken) {
            self.currentUser = user
            self.isLoggedIn = true
        }
    }

    func logout() {
        if let refreshToken = KeychainService.load(key: "refresh_token") {
            Task {
                await AuthService.logout(refreshToken: refreshToken)
            }
        }
        KeychainService.delete(key: "access_token")
        KeychainService.delete(key: "refresh_token")
        self.currentUser = nil
        self.isLoggedIn = false
    }

    /// Tenta di rinfrescare il token. Chiamata quando WebSocket riceve 4401.
    /// - Parameter onRefreshed: closure opzionale invocata (sul main actor) con il
    ///   nuovo access token se il refresh ha successo. Usata per riconnettere il WebSocket.
    func handleTokenExpiry(onRefreshed: ((String) -> Void)? = nil) async {
        guard let refreshToken = KeychainService.load(key: "refresh_token") else {
            self.logout()
            return
        }

        do {
            let newAccess = try await AuthService.refreshToken(refreshToken)
            KeychainService.save(key: "access_token", value: newAccess)
            if let user = decodeJWT(newAccess) {
                self.currentUser = user
            }
            onRefreshed?(newAccess)
        } catch {
            print("Refresh fallito, faccio logout: \(error.localizedDescription)")
            self.logout()
        }
    }

    /// Access token corrente
    var currentToken: String? {
        return KeychainService.load(key: "access_token")
    }
}
