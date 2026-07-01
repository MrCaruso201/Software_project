import SwiftUI

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

                        NavigationLink(value: DiscoveredServer(name: "Server manuale", host: manualIP, port: 8000, token: "miotokentest12345")) {
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
                    
                    // Server remoto (Tailscale Funnel)
                    NavigationLink(value: DiscoveredServer.remoteServer) {
                        HStack(spacing: 8) {
                            Image(systemName: "globe")
                                .foregroundColor(.kartAccent)
                            Text(DiscoveredServer.remoteServer.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.kartDim)
                                .font(.system(size: 12))
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.07))
                        .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

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
