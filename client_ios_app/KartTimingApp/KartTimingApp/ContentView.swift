import SwiftUI
import Combine
import Network

// ---------------------------------------------------------------------------
// MARK: - Modelli dati
// ---------------------------------------------------------------------------

struct TimingPayload {
    let updatedAt: String
    let headers: [String]
    let rows: [[String]]
    let url: String
}

struct DiscoveredServer: Identifiable, Equatable, Hashable {
    let id = UUID()
    let name: String
    let host: String
    let port: Int

    var wsURL: URL? { URL(string: "ws://\(host):\(port)/ws") }
}

// ---------------------------------------------------------------------------
// MARK: - Bonjour Browser
// ---------------------------------------------------------------------------

class ServerBrowser: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published var servers: [DiscoveredServer] = []

    private var browser = NetServiceBrowser()
    private var resolving: [NetService] = []

    override init() { super.init(); browser.delegate = self }

    func startBrowsing() {
        servers = []
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
        let server = DiscoveredServer(name: sender.name, host: host, port: sender.port)

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
// MARK: - Kart Timing Manager (WebSocket)
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// MARK: - Colori tema kart
// ---------------------------------------------------------------------------

extension Color {
    static let kartBG      = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let kartPanel   = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let kartAccent  = Color(red: 0.96, green: 0.77, blue: 0.09)   // giallo race
    static let kartGreen   = Color(red: 0.13, green: 0.76, blue: 0.37)
    static let kartRed     = Color(red: 0.93, green: 0.27, blue: 0.27)
    static let kartDim     = Color.white.opacity(0.35)
}

// ---------------------------------------------------------------------------
// MARK: - Server List View
// ---------------------------------------------------------------------------

struct ServerListView: View {
    @StateObject private var browser = ServerBrowser()
    @State private var manualIP = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Connessione manuale
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "network")
                                .foregroundColor(.kartDim)
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

                        NavigationLink(value: DiscoveredServer(name: "Server manuale", host: manualIP, port: 8000)) {
                            Text("Connetti manualmente")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(manualIP.isEmpty ? .kartDim : .black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(manualIP.isEmpty ? Color.white.opacity(0.08) : Color.kartAccent)
                                .cornerRadius(10)
                        }
                        .disabled(manualIP.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)

                    // Separatore
                    HStack {
                        Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.08))
                        Text("BONJOUR").font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim).padding(.horizontal, 10)
                        Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.08))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)

                    // Lista server scoperti
                    if browser.servers.isEmpty {
                        VStack(spacing: 14) {
                            ProgressView().tint(Color.kartAccent).scaleEffect(1.2)
                            Text("Cerco server sulla rete…")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(browser.servers) { server in
                            NavigationLink(value: server) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("\(server.host):\(server.port)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.kartDim)
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("🏁 Kart Live Timing")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { browser.startBrowsing() } label: {
                        Image(systemName: "arrow.clockwise").foregroundColor(.kartAccent)
                    }
                }
            }
            .navigationDestination(for: DiscoveredServer.self) { server in
                TimingView(server: server)
            }
            .onAppear { browser.startBrowsing() }
            .onDisappear { browser.stopBrowsing() }
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - Timing View (classifica live)
// ---------------------------------------------------------------------------

struct TimingView: View {
    let server: DiscoveredServer
    @StateObject private var manager = KartTimingManager()
    @State private var showURLSheet = false
    @State private var newURL = ""

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                statusBar

                // Classifica
                if let timing = manager.timing, !timing.rows.isEmpty {
                    timingTable(timing: timing)
                } else {
                    emptyState
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    newURL = manager.currentURL
                    showURLSheet = true
                } label: {
                    Image(systemName: "link.badge.plus").foregroundColor(.kartAccent)
                }
            }
        }
        .sheet(isPresented: $showURLSheet) {
            urlSheet
        }
        .onAppear { manager.connect(to: server) }
        .onDisappear { manager.disconnect() }
    }

    // ── Status bar ────────────────────────────────────────────────────────

    private var statusBar: some View {
        HStack(spacing: 10) {
            // Connessione
            HStack(spacing: 5) {
                Circle()
                    .fill(manager.isConnected ? Color.kartGreen : Color.kartRed)
                    .frame(width: 7, height: 7)
                Text(manager.isConnected ? "Connesso" : "Disconnesso")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(manager.isConnected ? .kartGreen : .kartRed)
            }

            Spacer()

            // Scraping live
            if manager.isScrapingActive {
                HStack(spacing: 4) {
                    Circle().fill(Color.kartAccent).frame(width: 5, height: 5)
                        .opacity(manager.timing != nil ? 1 : 0.4)
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.kartAccent)
                }
            }

            // Ultimo aggiornamento
            if let timing = manager.timing {
                Text(shortTime(timing.updatedAt))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kartPanel)
    }

    // ── Tabella classifica ────────────────────────────────────────────────

    @ViewBuilder
    private func timingTable(timing: TimingPayload) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header colonne
                if !timing.headers.isEmpty {
                    headerRow(timing.headers)
                }
                // Righe
                ForEach(Array(timing.rows.enumerated()), id: \.offset) { idx, row in
                    dataRow(row: row, headers: timing.headers, index: idx)
                }
            }
        }
    }

    private func headerRow(_ headers: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                Text(h.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.kartAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
        .background(Color(red: 0.12, green: 0.10, blue: 0.04))
    }

    private func dataRow(row: [String], headers: [String], index: Int) -> some View {
        let isFirst = row.first == "1"
        let bg: Color = isFirst
            ? Color.kartAccent.opacity(0.08)
            : (index % 2 == 0 ? Color.kartPanel : Color.kartBG)

        return HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { colIdx, val in
                Text(val)
                    .font(.system(size: 13, weight: colIdx == 0 ? .bold : .regular,
                                  design: .monospaced))
                    .foregroundColor(colIdx == 0 && isFirst ? .kartAccent : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            // Riempi celle mancanti
            if row.count < headers.count {
                ForEach(row.count..<headers.count, id: \.self) { _ in
                    Text("").frame(maxWidth: .infinity)
                }
            }
        }
        .background(bg)
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color.white.opacity(0.05)),
            alignment: .bottom
        )
    }

    // ── Empty state ───────────────────────────────────────────────────────

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            if manager.isConnected {
                ProgressView().tint(Color.kartAccent).scaleEffect(1.3)
                Text("Attendo dati dal kartdromo…")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(.kartDim)
            } else {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 40))
                    .foregroundColor(.kartDim)
                Text("Connessione persa")
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // ── URL Sheet ─────────────────────────────────────────────────────────

    private var urlSheet: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("URL kartdromo")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.kartDim)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("https://live.racefacer.com/...", text: $newURL)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(12)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(10)

                    Button {
                        if newURL.hasPrefix("http") {
                            manager.sendCommand("set_url", extra: ["url": newURL])
                            showURLSheet = false
                        }
                    } label: {
                        Text("Aggiorna URL")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.kartAccent)
                            .cornerRadius(12)
                    }

                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Cambia sorgente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annulla") { showURLSheet = false }
                        .foregroundColor(.kartAccent)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private func shortTime(_ iso: String) -> String {
        let parts = iso.split(separator: "T")
        guard parts.count == 2 else { return iso }
        return String(parts[1].prefix(8))
    }
}

// ---------------------------------------------------------------------------
// MARK: - Entry point
// ---------------------------------------------------------------------------

@main
struct KartTimingApp: App {
    var body: some Scene {
        WindowGroup {
            ServerListView()
        }
    }
}
