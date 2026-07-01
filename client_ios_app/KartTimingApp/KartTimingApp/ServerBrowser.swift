import Foundation
import Combine
import Network

class ServerBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var servers: [DiscoveredServer] = []

    private var browser = NetServiceBrowser()
    private var resolving: [NetService] = []

    override init() { super.init(); browser.delegate = self }

    func startBrowsing() {
        stopBrowsing()
        servers = []
        resolving = []
        browser.searchForServices(ofType: "_karttiming._tcp.", inDomain: "local.")
    }

    func stopBrowsing() { browser.stop() }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        servers.removeAll { $0.name == service.name }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses, let data = addresses.first else { return }

        var storage = sockaddr_storage()
        (data as NSData).getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)

        var host = ""
        if storage.ss_family == UInt8(AF_INET) {
            var addr = withUnsafePointer(to: &storage) {
                $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            }
            var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
            host = String(cString: buffer)
        }

        guard !host.isEmpty else { return }
        let server = DiscoveredServer(
                        name: sender.name,
                        host: host,
                        port: sender.port,
                        token: "miotokentest12345")

        DispatchQueue.main.async {
            if !self.servers.contains(where: { $0.host == server.host && $0.port == server.port }) {
                self.servers.append(server)
            }
        }
        resolving.removeAll { $0 === sender }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.removeAll { $0 === sender }
    }
}
