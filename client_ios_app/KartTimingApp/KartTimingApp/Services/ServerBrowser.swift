import Foundation
import Combine

/// Gestisce la scoperta dei server locali tramite mDNS (Bonjour).
class ServerBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var discoveredServers: [DiscoveredServer] = []
    
    private var netServiceBrowser: NetServiceBrowser!
    private var resolvingServices: [NetService] = []
    
    override init() {
        super.init()
        netServiceBrowser = NetServiceBrowser()
        netServiceBrowser.delegate = self
    }
    
    func startBrowsing() {
        discoveredServers.removeAll()
        resolvingServices.removeAll()
        netServiceBrowser.searchForServices(ofType: "_karttiming._tcp.", inDomain: "local.")
    }
    
    func stopBrowsing() {
        netServiceBrowser.stop()
        resolvingServices.removeAll()
    }
    
    // MARK: - NetServiceBrowserDelegate
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("Trovato servizio: \(service.name)")
        resolvingServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        print("Rimosso servizio: \(service.name)")
        DispatchQueue.main.async {
            self.discoveredServers.removeAll { $0.name == service.name }
        }
        resolvingServices.removeAll { $0 == service }
    }
    
    // MARK: - NetServiceDelegate
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = sender.hostName else { return }
        
        let port = sender.port
        let name = sender.name
        
        DispatchQueue.main.async {
            // Rimuovi se c'è già
            self.discoveredServers.removeAll { $0.name == name }
            
            // Aggiungiamo
            let newServer = DiscoveredServer(
                name: name,
                host: hostName,
                port: port,
                useTLS: false,
                token: nil
            )
            self.discoveredServers.append(newServer)
        }
        
        resolvingServices.removeAll { $0 == sender }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Errore nella risoluzione del servizio: \(sender.name) - \(errorDict)")
        resolvingServices.removeAll { $0 == sender }
    }
}
