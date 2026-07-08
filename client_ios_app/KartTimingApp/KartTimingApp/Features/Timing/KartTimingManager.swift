import Foundation
import Combine

class KartTimingManager: ObservableObject {
    @Published var timing: TimingPayload? = nil
    @Published var isConnected: Bool = false
    @Published var currentURL: String = ""
    @Published var isScrapingActive: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var currentServer: DiscoveredServer?

    func connect(to server: DiscoveredServer) {
        disconnect()
        currentServer = server
        guard let url = server.wsURL else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        DispatchQueue.main.async { self.isConnected = true }
        listen()
        // Chiedi subito lo stato
        sendCommand("get_status")
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.timing = nil
            self.isScrapingActive = false
        }
    }

    /// Riconnette al server con un nuovo DiscoveredServer (es. token aggiornato).
    /// Chiamato da AuthState dopo un token refresh per ripristinare la sessione WebSocket.
    func reconnect(to server: DiscoveredServer) {
        connect(to: server)
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleMessage(text) }
                self.listen()
            case .failure:
                let code = self.webSocketTask?.closeCode.rawValue
                let storedServer = self.currentServer
                DispatchQueue.main.async {
                    self.isConnected = false
                    if code == 4401, let storedServer {
                        // Token scaduto: prova il refresh e riconnetti con il nuovo token
                        Task {
                            await AuthState.shared.handleTokenExpiry { newToken in
                                let updatedServer = DiscoveredServer(
                                    name:   storedServer.name,
                                    host:   storedServer.host,
                                    port:   storedServer.port,
                                    useTLS: storedServer.useTLS,
                                    token:  newToken
                                )
                                self.reconnect(to: updatedServer)
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        DispatchQueue.main.async {
            switch type {
            case "timing_update":
                let headers = json["headers"] as? [String] ?? []
                let rawRows = json["rows"] as? [[String]] ?? []
                let updatedAt = json["updated_at"] as? String ?? ""
                let url = json["url"] as? String ?? ""
                self.timing = TimingPayload(updatedAt: updatedAt, headers: headers, rows: rawRows, url: url)
                self.isScrapingActive = true

            case "status":
                self.currentURL = json["url"] as? String ?? ""
                self.isScrapingActive = json["scraping"] as? Bool ?? false

            case "url_changed":
                self.currentURL = json["url"] as? String ?? ""

            case "error":
                if let msg = json["message"] as? String {
                    self.errorMessage = msg
                    self.showError = true
                }

            default:
                break
            }
        }
    }

    func sendCommand(_ command: String, extra: [String: String] = [:]) {
        var payload: [String: String] = ["command": command]
        payload.merge(extra) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }
}
