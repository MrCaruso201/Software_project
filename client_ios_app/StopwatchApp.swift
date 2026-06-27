import SwiftUI
import Combine
import Network

// ---------------------------------------------------------------------------
// MARK: - Bonjour Browser
// ---------------------------------------------------------------------------

struct DiscoveredServer: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int

    var wsURL: URL? {
        URL(string: "ws://\(host):\(port)/ws")
    }
}

class ServerBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var servers: [DiscoveredServer] = []

    private var browser = NetServiceBrowser()
    private var resolving: [NetService] = []

    override init() {
        super.init()
        browser.delegate = self
    }

    func startBrowsing() {
        servers = []
        browser.searchForServices(ofType: "_stopwatch._tcp.", inDomain: "local.")
    }

    func stopBrowsing() {
        browser.stop()
    }

    // Trovato un servizio
    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didFind service: NetService,
                           moreComing: Bool) {
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 5)
    }

    // Servizio rimosso dalla rete
    func netServiceBrowser(_ browser: NetServiceBrowser,
                           didRemove service: NetService,
                           moreComing: Bool) {
        servers.removeAll { $0.name == service.name }
    }

    // Risolto l'indirizzo IP
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard
            let addresses = sender.addresses,
            let data = addresses.first
        else { return }

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
            port: sender.port
        )

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

// ---------------------------------------------------------------------------
// MARK: - WebSocket Manager
// ---------------------------------------------------------------------------

class StopwatchManager: ObservableObject {
    @Published var displayValue: String = "00:00.00"
    @Published var isRunning: Bool = false
    @Published var isConnected: Bool = false

    private var webSocketTask: URLSessionWebSocketTask?

    func connect(to server: DiscoveredServer) {
        disconnect()
        guard let url = server.wsURL else { return }
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        DispatchQueue.main.async { self.isConnected = true }
        listenForMessages()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.displayValue = "00:00.00"
            self.isRunning = false
        }
    }

    private func listenForMessages() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self?.handleMessage(text)
                }
                self?.listenForMessages()
            case .failure:
                DispatchQueue.main.async { self?.isConnected = false }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String,
            type == "tick",
            let value = json["value"] as? Double,
            let running = json["running"] as? Bool
        else { return }

        DispatchQueue.main.async {
            self.displayValue = Self.format(value)
            self.isRunning = running
        }
    }

    func sendCommand(_ command: String) {
        let payload = #"{"command": "\#(command)"}"#
        webSocketTask?.send(.string(payload)) { _ in }
    }

    static func format(_ totalSeconds: Double) -> String {
        let minutes = Int(totalSeconds) / 60
        let seconds = Int(totalSeconds) % 60
        let centesimi = Int((totalSeconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centesimi)
    }
}

// ---------------------------------------------------------------------------
// MARK: - Schermata selezione server
// ---------------------------------------------------------------------------

struct ServerListView: View {
    @StateObject private var browser = ServerBrowser()
    @State private var showManualEntry = false
    @State private var manualIP = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.07, green: 0.07, blue: 0.10).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Campo IP manuale
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "network")
                                .foregroundColor(.white.opacity(0.4))
                            TextField("IP manuale (es. 192.168.1.10)", text: $manualIP)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.white)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.numbersAndPunctuation)
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(10)

                        NavigationLink(value: DiscoveredServer(
                            name: "Server manuale",
                            host: manualIP,
                            port: 8000
                        )) {
                            Text("Connetti")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(manualIP.isEmpty
                                    ? Color.white.opacity(0.1)
                                    : Color(red: 0.18, green: 0.72, blue: 0.46))
                                .cornerRadius(10)
                        }
                        .disabled(manualIP.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.vertical, 16)

                    // Lista server scoperti via Bonjour
                    if browser.servers.isEmpty {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.2)
                            Text("Cerco server sulla rete…")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                            Text("(funziona su iPhone fisico)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.2))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(browser.servers) { server in
                            NavigationLink(value: server) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.name)
                                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                    Text("\(server.host):\(server.port)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Server disponibili")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { browser.startBrowsing() }) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.white)
                    }
                }
            }
            .navigationDestination(for: DiscoveredServer.self) { server in
                StopwatchView(server: server)
            }
            .onAppear { browser.startBrowsing() }
            .onDisappear { browser.stopBrowsing() }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Schermata cronometro
// ---------------------------------------------------------------------------

struct StopwatchView: View {
    let server: DiscoveredServer
    @StateObject private var manager = StopwatchManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.10).ignoresSafeArea()

            VStack(spacing: 48) {
                // Indicatore connessione
                HStack(spacing: 6) {
                    Circle()
                        .fill(manager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(manager.isConnected ? "Connesso a \(server.name)" : "Connessione persa")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Display cronometro
                VStack(spacing: 8) {
                    Text("CRONOMETRO")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(4)
                        .foregroundColor(Color.white.opacity(0.4))

                    Text(manager.displayValue)
                        .font(.system(size: 64, weight: .thin, design: .monospaced))
                        .foregroundColor(.white)
                        .contentTransition(.numericText())
                        .animation(.linear(duration: 0.05), value: manager.displayValue)

                    HStack(spacing: 6) {
                        if manager.isRunning {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("IN ESECUZIONE")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(Color.red.opacity(0.8))
                        } else {
                            Text("FERMO")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(Color.white.opacity(0.3))
                        }
                    }
                    .frame(height: 20)
                }

                Spacer()

                // Bottoni
                VStack(spacing: 16) {
                    Button(action: {
                        manager.sendCommand(manager.isRunning ? "stop" : "start")
                    }) {
                        Label(
                            manager.isRunning ? "Stop" : "Start",
                            systemImage: manager.isRunning ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(manager.isRunning
                            ? Color(red: 0.85, green: 0.25, blue: 0.25)
                            : Color(red: 0.18, green: 0.72, blue: 0.46))
                        .cornerRadius(16)
                    }

                    Button(action: { manager.sendCommand("reset") }) {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(false)
        .onAppear { manager.connect(to: server) }
        .onDisappear { manager.disconnect() }
    }
}

