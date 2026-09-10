import Foundation
import Combine

class KartTimingManager: ObservableObject {
    @Published var timing: TimingPayload? = nil
    @Published var isConnected: Bool = false
    @Published var currentURL: String = ""
    @Published var isScrapingActive: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showError: Bool = false
    @Published var lastEventUpdate: Date? = nil
    let pitUpdates = PassthroughSubject<PitUpdate, Never>()

    struct PitUpdate {
        let eventId: Int
        let kartNumber: Int
        let requestId: String?
    }

    private var webSocketSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentServer: DiscoveredServer?

    func connect(to server: DiscoveredServer) {
        disconnect()
        currentServer = server
        guard let url = server.wsURL else { return }
        let session = URLSession(configuration: .default)
        webSocketSession = session
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
        webSocketSession?.invalidateAndCancel()
        webSocketSession = nil
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
        guard let socket = webSocketTask else { return }
        socket.receive { [weak self] result in
            guard let self, self.webSocketTask === socket else { return }
            switch result {
            case .success(let message):
                if case .string(let text) = message { self.handleMessage(text, socket: socket) }
                self.listen()
            case .failure:
                let code = self.webSocketTask?.closeCode.rawValue
                let storedServer = self.currentServer
                DispatchQueue.main.async {
                    guard self.webSocketTask === socket else { return }
                    self.isConnected = false
                    if code == 4401, let storedServer {
                        // Token scaduto: prova il refresh e riconnetti con il nuovo token
                        Task {
                            await AuthState.shared.handleTokenExpiry { newToken in
                                guard self.webSocketTask === socket else { return }
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

    private func handleMessage(_ text: String, socket: URLSessionWebSocketTask) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return }

        DispatchQueue.main.async {
            guard self.webSocketTask === socket else { return }
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

            case "event_update":
                if json["change"] as? String == "pit",
                   let eventId = json["event_id"] as? Int,
                   let kartNumber = json["kart_number"] as? Int {
                    self.pitUpdates.send(PitUpdate(eventId: eventId, kartNumber: kartNumber,
                                                   requestId: json["request_id"] as? String))
                } else {
                    // Older servers and other changes retain the general refresh path.
                    self.lastEventUpdate = Date()
                }

            default:
                break
            }
        }
    }

    func sendCommand(_ command: String, extra: [String: Any] = [:]) {
        var payload: [String: Any] = ["command": command]
        payload.merge(extra) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { _ in }
    }

    func subscribeToEvent(_ eventId: Int) {
        sendCommand("subscribe_event", extra: ["event_id": eventId])
    }
}
