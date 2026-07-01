import Foundation
import Combine

class KartTimingManager: ObservableObject {
    @Published var timing: TimingPayload? = nil
    @Published var isConnected: Bool = false
    @Published var currentURL: String = ""
    @Published var isScrapingActive: Bool = false

    private var webSocketTask: URLSessionWebSocketTask?

    func connect(to server: DiscoveredServer) {
        disconnect()
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

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message { self?.handleMessage(text) }
                self?.listen()
            case .failure:
                DispatchQueue.main.async { self?.isConnected = false }
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
                print("Server error:", json["message"] ?? "")

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
