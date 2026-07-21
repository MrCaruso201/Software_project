import SwiftUI

struct UserHomeView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = UserHomeViewModel()
    
    @State private var showNotifications = false
    
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
                    showNotifications = true
                }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .foregroundColor(.kartAccent)

                        if viewModel.unreadCount > 0 {
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 16, height: 16)
                                Text(viewModel.unreadCount > 9 ? "9+" : "\(viewModel.unreadCount)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .offset(x: 8, y: -8)
                        }
                    }
                }
                .sheet(isPresented: $showNotifications) {
                    NotificationsPanelView(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            viewModel.fetchData(serverURL: server.httpURL, token: authState.currentToken)
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
            let waitlistRegs = viewModel.registrations.filter { $0.status == "waitlist" }
            
            if pendingRegs.isEmpty && waitlistRegs.isEmpty && viewModel.totalRegistrations == 0 {
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
                                .foregroundColor(.kartDim)
                        }
                        .padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    if !waitlistRegs.isEmpty {
                        ForEach(waitlistRegs, id: \.id) { reg in
                            if let event = viewModel.events.first(where: { $0.id == reg.eventId }) {
                                waitlistEventRow(event: event)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.kartPanel)
        .cornerRadius(12)
    }
    
    private func pendingEventRow(event: RaceEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("In attesa di pagamento")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.kartPanel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }
    
    private func waitlistEventRow(event: RaceEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .foregroundColor(.purple)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                Text("In Lista d'Attesa")
                    .font(.system(size: 12))
                    .foregroundColor(.purple)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.kartPanel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.3), lineWidth: 1))
    }
}
