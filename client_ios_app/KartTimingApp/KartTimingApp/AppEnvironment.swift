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

#if canImport(UIKit)
import UIKit

class KeyboardDismissManager: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissManager()
    
    func setupGlobalTapToDismissKeyboard() {
        guard let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.windows.first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.setupGlobalTapToDismissKeyboard()
            }
            return
        }
        
        let tapGesture = UITapGestureRecognizer(target: window, action: #selector(UIView.endEditing))
        tapGesture.requiresExclusiveTouchType = false
        tapGesture.cancelsTouchesInView = false
        tapGesture.delegate = self
        window.addGestureRecognizer(tapGesture)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let view = touch.view {
            let className = String(describing: type(of: view))
            if className.contains("TextField") || 
               className.contains("TextView") || 
               className.contains("Button") || 
               className.contains("Picker") || 
               className.contains("Slider") ||
               className.contains("Switch") ||
               className.contains("Cell") ||
               view is UIControl {
                return false
            }
        }
        return true
    }
}
#endif
