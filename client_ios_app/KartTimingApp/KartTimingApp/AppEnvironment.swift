import Foundation
import Combine

/// Gestisce la modalità di sviluppo (DEV MODE).
///
/// Quando `devModeEnabled == true` tutta la comunicazione viene instradata
/// verso il server locale rilevato via Bonjour/mDNS (host configurabile).
/// Il flag viene persisto in UserDefaults così sopravvive al riavvio dell'app.
class AppEnvironment: ObservableObject {

    static let shared = AppEnvironment()

    // MARK: - Costanti server

    /// URL pubblico (Tailscale Funnel) — usato in produzione
    static let productionBaseURL = "https://marcos-macbook-pro.tail71e118.ts.net"

    // MARK: - Stato osservabile

    @Published var devModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(devModeEnabled, forKey: "devModeEnabled")
        }
    }
    
    @Published var selectedLocalHost: String? {
        didSet { UserDefaults.standard.set(selectedLocalHost, forKey: "selectedLocalHost") }
    }
    
    @Published var selectedLocalPort: Int? {
        didSet { UserDefaults.standard.set(selectedLocalPort, forKey: "selectedLocalPort") }
    }

    // MARK: - Init

    private init() {
        self.devModeEnabled = UserDefaults.standard.bool(forKey: "devModeEnabled")
        self.selectedLocalHost = UserDefaults.standard.string(forKey: "selectedLocalHost")
        let savedPort = UserDefaults.standard.integer(forKey: "selectedLocalPort")
        self.selectedLocalPort = savedPort == 0 ? nil : savedPort
    }

    // MARK: - URL corrente

    /// Base URL da usare nelle chiamate REST (senza slash finale)
    var baseURL: String {
        if devModeEnabled, let host = selectedLocalHost, let port = selectedLocalPort {
            return "http://\(host):\(port)"
        }
        return AppEnvironment.productionBaseURL
    }

    /// Costruisce il `DiscoveredServer` corretto in base alla modalità attiva
    func server(token: String) -> DiscoveredServer {
        devModeEnabled ? .localServer(token: token) : .remoteServer(token: token)
    }
}
