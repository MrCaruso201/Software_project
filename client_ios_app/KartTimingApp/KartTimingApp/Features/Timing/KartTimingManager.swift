import Foundation
import Combine

class KartTimingManager: ObservableObject {
    @Published var timing: TimingPayload? = nil
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var currentURL: String = ""
    @Published var isScrapingActive: Bool = false
    @Published var errorMessage: String? = nil
    @Published var sourceError: String? = nil
    @Published var showError: Bool = false
    @Published var lastEventUpdate: Date? = nil
    let flagUpdates = PassthroughSubject<FlagUpdate, Never>()
    struct FlagUpdate {
        let eventId: Int
        let change: String
        let kartsChanged: Bool
        let requestId: String?
    }
    let pitUpdates = PassthroughSubject<PitUpdate, Never>()

    struct PitUpdate {
        let eventId: Int
        let kartNumber: Int
        let requestId: String?
    }

    private var webSocketSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentServer: DiscoveredServer?
    private var heartbeatTimeout: DispatchWorkItem?
    private var heartbeatScheduled = false
    private var selectedURL: String?
    private var subscribedEventId: Int?

    func connect(to server: DiscoveredServer, preservingTiming: Bool = false) {
        disconnect(preservingTiming: preservingTiming)
        let server = DiscoveredServer(
            name: server.name, host: server.host, port: server.port,
            useTLS: server.useTLS, token: AuthState.shared.currentToken ?? server.token
        )
        currentServer = server
        guard let url = server.wsURL else { return }
        let session = URLSession(configuration: .default)
        webSocketSession = session
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnecting = true
        sourceError = nil
        errorMessage = nil
        showError = false
        if let socket = webSocketTask {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.webSocketTask === socket, self.isConnecting else { return }
                self.disconnect(preservingTiming: true)
            }
        }
        listen()
        // Chiedi subito lo stato
        sendCommand("get_status")
    }

    func disconnect(preservingTiming: Bool = false) {
        heartbeatTimeout?.cancel()
        heartbeatTimeout = nil
        heartbeatScheduled = false
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        webSocketSession?.invalidateAndCancel()
        webSocketSession = nil
        isConnected = false
        isConnecting = false
        if !preservingTiming { timing = nil }
        isScrapingActive = false
        currentURL = ""
        selectedURL = nil
        subscribedEventId = nil
    }

    /// Riconnette al server con un nuovo DiscoveredServer (es. token aggiornato).
    /// Chiamato da AuthState dopo un token refresh per ripristinare la sessione WebSocket.
    func reconnect(to server: DiscoveredServer) {
        let url = selectedURL
        let eventId = subscribedEventId
        connect(to: server)
        if let url { sendCommand("set_url", extra: ["url": url]) }
        if let eventId { subscribeToEvent(eventId) }
    }

    // Verifica anche le interruzioni di rete che non chiudono subito il socket.
    private func startHeartbeat(socket: URLSessionWebSocketTask) {
        guard !heartbeatScheduled else { return }
        heartbeatScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.webSocketTask === socket, self.isConnected else { return }
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.webSocketTask === socket else { return }
                self.disconnect(preservingTiming: true)
            }
            self.heartbeatTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
            socket.sendPing { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, self.webSocketTask === socket else { return }
                    self.heartbeatTimeout?.cancel()
                    self.heartbeatTimeout = nil
                    self.heartbeatScheduled = false
                    if error != nil {
                        self.disconnect(preservingTiming: true)
                    } else {
                        self.startHeartbeat(socket: socket)
                    }
                }
            }
        }
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
                    self.heartbeatTimeout?.cancel()
                    self.heartbeatScheduled = false
                    self.isConnected = false
                    self.isConnecting = false
                    self.isScrapingActive = false
                    self.currentURL = ""
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
            self.isConnecting = false
            self.isConnected = true
            self.startHeartbeat(socket: socket)
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
                    if msg.localizedCaseInsensitiveContains("dominio non consentito") {
                        self.sourceError = msg
                        self.timing = nil
                        self.isScrapingActive = false
                        self.showError = false
                    } else {
                        self.showError = true
                    }
                }

            case "event_update":
                if let change = json["change"] as? String, ["messages", "penalties"].contains(change),
                   let eventId = json["event_id"] as? Int {
                    self.flagUpdates.send(FlagUpdate(eventId: eventId, change: change,
                        kartsChanged: json["karts_changed"] as? Bool ?? false,
                        requestId: json["request_id"] as? String))
                } else if json["change"] as? String == "pit",
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
        if command == "set_url" {
            selectedURL = extra["url"] as? String
            sourceError = nil
            timing = nil
            isScrapingActive = false
        }
        if command == "subscribe_event" { subscribedEventId = extra["event_id"] as? Int }
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
