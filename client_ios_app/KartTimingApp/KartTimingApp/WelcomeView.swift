import SwiftUI

struct WelcomeView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                // Sfondo (usiamo lo stesso dell'app)
                Color.kartBG.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    
                    Spacer()
                    
                    Text("Race Manager")
                        .font(.system(size: 40, weight: .heavy, design: .default))
                        .foregroundColor(.white)
                        .padding(.bottom, 40)
                    
                    // 1. Pulsante Login
                    NavigationLink(destination: Text("Schermata Login (In Arrivo)")) {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title3)
                            Text("Login")
                                .font(.title2.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.kartAccent)
                        .cornerRadius(16)
                        .shadow(color: Color.kartAccent.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    
                    // 2. Pulsante per Live Timing
                    NavigationLink(value: DiscoveredServer.remoteServer) {
                        HStack {
                            Image(systemName: "stopwatch.fill")
                                .font(.title3)
                            Text("Live Timing")
                                .font(.title2.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.kartPanel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .cornerRadius(16)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 30)
            }
            // Necessario per colorare bene la barra di navigazione
            .toolbarColorScheme(.dark, for: .navigationBar) 
            .navigationDestination(for: DiscoveredServer.self) { server in
                TimingView(server: server)
            }
        }
    }
}
