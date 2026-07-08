import SwiftUI

struct UserHomeView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = UserHomeViewModel()
    
    @State private var activePaymentEvent: RaceEvent? = nil
    
    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView().tint(.kartAccent).scaleEffect(1.3)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        profileCard
                        notificationsCard
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    // Notifiche (placeholder)
                }) {
                    Image(systemName: "bell.fill")
                        .foregroundColor(.kartAccent)
                }
            }
        }
        .onAppear {
            viewModel.fetchData(serverURL: server.httpURL, token: authState.currentToken)
        }
        .sheet(item: $activePaymentEvent) { event in
            PaymentInfoSheetView(event: event)
                .environmentObject(authState)
        }
    }
    
    // MARK: - Profile Card
    private var profileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                if let profilePictureURL = viewModel.profile?.profilePictureURL,
                   let url = URL(string: server.httpURL?.absoluteString.replacingOccurrences(of: "/api", with: "") ?? "")?.appendingPathComponent(String(profilePictureURL.dropFirst())) {
                    AsyncImage(url: url) { phase in
                        if let img = phase.image {
                            img.resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                        } else if phase.error != nil {
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .frame(width: 60, height: 60)
                                .foregroundColor(.kartAccent)
                        } else {
                            ProgressView()
                                .frame(width: 60, height: 60)
                        }
                    }
                } else {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.kartAccent)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    if let p = viewModel.profile {
                        let hasName = (p.firstName != nil && !p.firstName!.isEmpty) || (p.lastName != nil && !p.lastName!.isEmpty)
                        if hasName {
                            Text("\(p.firstName ?? "") \(p.lastName ?? "")")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("@\(p.username)")
                                .font(.subheadline)
                                .foregroundColor(.kartDim)
                        } else {
                            Text("@\(p.username)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    } else {
                        Text("Utente")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                Spacer()
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            HStack(spacing: 0) {
                statView(title: "Totali", value: "\(viewModel.totalRegistrations)")
                Divider().background(Color.white.opacity(0.2)).frame(height: 30)
                statView(title: "Confermate", value: "\(viewModel.confirmedRegistrations)")
                Divider().background(Color.white.opacity(0.2)).frame(height: 30)
                statView(title: "Da Pagare", value: "\(viewModel.pendingRegistrations)")
            }
        }
        .padding(16)
        .background(Color.kartPanel)
        .cornerRadius(12)
    }
    
    private func statView(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.kartAccent)
            Text(title)
                .font(.caption)
                .foregroundColor(.kartDim)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Notifications / Registrations Card
    private var notificationsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Iscrizioni e Avvisi")
                .font(.headline)
                .foregroundColor(.white)
            
            let pendingRegs = viewModel.registrations.filter { $0.status == "pending_payment" }
            
            if pendingRegs.isEmpty && viewModel.totalRegistrations == 0 {
                Text("Non hai ancora effettuato nessuna iscrizione.")
                    .font(.subheadline)
                    .foregroundColor(.kartDim)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 12) {
                    ForEach(pendingRegs, id: \.id) { reg in
                        if let event = viewModel.events.first(where: { $0.id == reg.eventId }) {
                            pendingEventRow(event: event)
                        }
                    }
                    
                    let confirmedCount = viewModel.confirmedRegistrations
                    if confirmedCount > 0 {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Hai \(confirmedCount) iscrizion\(confirmedCount == 1 ? "e" : "i") confermat\(confirmedCount == 1 ? "a" : "e").")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.kartPanel)
        .cornerRadius(12)
    }
    
    private func pendingEventRow(event: RaceEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Pagamento in sospeso")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
            }
            
            Text(event.title)
                .font(.body)
                .foregroundColor(.white)
            
            Button {
                activePaymentEvent = event
            } label: {
                Text("Paga Ora")
                    .font(.system(size: 14, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
