import Foundation
import Combine

@MainActor
class AuthState: ObservableObject {
    @Published var isLoggedIn: Bool = false
    @Published var currentUser: LoggedInUser? = nil
    /// true quando l'utente è entrato tramite "Live Timing senza accesso"
    @Published var isGuestSession: Bool = false

    static let shared = AuthState()
    private var sessionGeneration = UUID()
    @Published private(set) var uploadedAvatarPath: String?
    @Published private(set) var avatarRevision = UUID()

    func didUploadAvatar(path: String) {
        uploadedAvatarPath = path
        avatarRevision = UUID()
    }

    func avatarURL(path: String?, serverURL: URL?) -> URL? {
        guard let path = uploadedAvatarPath ?? path,
              let serverURL,
              let url = URL(string: path, relativeTo: serverURL)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = (components.queryItems ?? []) + [
            URLQueryItem(name: "v", value: avatarRevision.uuidString)
        ]
        return components.url
    }

    init() {
        // Al lancio, verifica se c'è un token salvato nel Keychain.
        // Se l'account è "viewer" (sessione guest) i token vengono eliminati
        // immediatamente: la sessione guest non deve essere ricordata.
        if let token = KeychainService.load(key: "access_token"),
           let user = decodeJWT(token) {
            if user.role == .viewer {
                KeychainService.delete(key: "access_token")
                KeychainService.delete(key: "refresh_token")
                // Non impostiamo isLoggedIn → l'app mostra LoginView
            } else {
                self.currentUser = user
                self.isLoggedIn = true
            }
        }
    }

    func setLoginData(accessToken: String, refreshToken: String, guestSession: Bool = false) {
        sessionGeneration = UUID()
        uploadedAvatarPath = nil
        avatarRevision = UUID()
        KeychainService.save(key: "access_token", value: accessToken)
        KeychainService.save(key: "refresh_token", value: refreshToken)
        if let user = decodeJWT(accessToken) {
            self.currentUser = user
            self.isLoggedIn = true
            self.isGuestSession = guestSession
        }
    }

    func logout() {
        sessionGeneration = UUID()
        uploadedAvatarPath = nil
        avatarRevision = UUID()
        if let refreshToken = KeychainService.load(key: "refresh_token") {
            Task {
                await AuthService.logout(refreshToken: refreshToken)
            }
        }
        KeychainService.delete(key: "access_token")
        KeychainService.delete(key: "refresh_token")
        self.currentUser = nil
        self.isLoggedIn = false
        self.isGuestSession = false
    }

    /// Tenta di rinfrescare il token e lo restituisce (nuova versione per NetworkService)
    func handleTokenExpiryWithReturn() async -> String? {
        guard let refreshToken = KeychainService.load(key: "refresh_token") else {
            self.logout()
            return nil
        }

        let generation = sessionGeneration
        do {
            let newAccess = try await AuthService.refreshToken(refreshToken)
            guard generation == sessionGeneration, !Task.isCancelled else { return nil }
            KeychainService.save(key: "access_token", value: newAccess)
            if let user = decodeJWT(newAccess) {
                self.currentUser = user
            }
            return newAccess
        } catch {
            guard generation == sessionGeneration, !Task.isCancelled else { return nil }
            if case AuthError.refreshRejected = error { self.logout() }
            return nil
        }
    }

    /// Tenta di rinfrescare il token. Chiamata quando WebSocket riceve 4401.
    /// - Parameter onRefreshed: closure opzionale invocata (sul main actor) con il
    ///   nuovo access token se il refresh ha successo. Usata per riconnettere il WebSocket.
    func handleTokenExpiry(onRefreshed: ((String) -> Void)? = nil) async {
        if let newAccess = await handleTokenExpiryWithReturn() {
            onRefreshed?(newAccess)
        }
    }

    /// Access token corrente
    var currentToken: String? {
        return KeychainService.load(key: "access_token")
    }
}
