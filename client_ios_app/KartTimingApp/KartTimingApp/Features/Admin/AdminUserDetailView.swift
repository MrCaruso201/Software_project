import SwiftUI

struct AdminUserDetailView: View {
    let user: UserProfile
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = AdminUserSearchViewModel()
    
    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            if viewModel.isLoading {
                ProgressView().tint(.kartAccent).scaleEffect(1.3)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        profileCard
                        registrationsCard
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Dettaglio Utente")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.setup(serverURL: server.httpURL, token: authState.currentToken)
            viewModel.fetchUserDetails(targetUserId: user.id)
        }
    }
    
    private var profileCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.kartAccent)
                
                VStack(alignment: .leading, spacing: 4) {
                    let hasName = (user.firstName != nil && !user.firstName!.isEmpty) || (user.lastName != nil && !user.lastName!.isEmpty)
                    if hasName {
                        Text("\(user.firstName ?? "") \(user.lastName ?? "")")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("@\(user.username)")
                            .font(.subheadline)
                            .foregroundColor(.kartDim)
                    } else {
                        Text("@\(user.username)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color.kartPanel)
        .cornerRadius(12)
    }
    
    private var registrationsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text("ISCRIZIONI UTENTE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
                Text("\(viewModel.userRegistrations.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.kartAccent.opacity(0.08))

            if viewModel.userRegistrations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "flag.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.kartDim.opacity(0.4))
                    Text("Nessuna iscrizione")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.kartDim)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                let sorted = viewModel.userRegistrations.sorted { r0, r1 in
                    let d0 = viewModel.allEvents.first(where: { $0.id == r0.eventId })?.dateObject ?? .distantFuture
                    let d1 = viewModel.allEvents.first(where: { $0.id == r1.eventId })?.dateObject ?? .distantFuture
                    return d0 > d1 // Ordine decrescente (più recenti prima)
                }

                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, reg in
                        if let event = viewModel.allEvents.first(where: { $0.id == reg.eventId }) {
                            // REINDIRIZZA A AdminEventRegistrationsView
                            NavigationLink {
                                // EventiViewModel serve per la view di gestione
                                let eventiVM = EventiViewModel()
                                AdminEventRegistrationsView(server: server, viewModel: eventiVM, event: event)
                            } label: {
                                registrationRow(reg: reg, event: event)
                            }
                            .buttonStyle(.plain)

                            if idx < sorted.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 58)
                            }
                        }
                    }
                }
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
    
    private func registrationRow(reg: EventRegistrationResponse, event: RaceEvent) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor(reg.status).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: statusIcon(reg.status))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(statusColor(reg.status))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if let date = event.dateObject {
                        Label(date.formatted(.dateTime.day().month(.abbreviated).year()),
                              systemImage: "calendar")
                            .font(.system(size: 11))
                            .foregroundColor(.kartDim)
                    }
                    let city = event.location.components(separatedBy: " - ").first ?? event.location
                    Label(city, systemImage: "mappin.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                        .lineLimit(1)
                }
                
                if reg.hasSignedRelease == true {
                    Label("Liberatoria Firmata", systemImage: "signature")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(statusLabel(reg.status))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor(reg.status))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor(reg.status).opacity(0.14))
                    .cornerRadius(5)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.kartDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
    
    private func statusColor(_ status: String) -> Color {
        switch status {
        case "confirmed":       return .green
        case "pending_payment": return .orange
        case "waitlist":        return .purple
        default:                return .kartDim
        }
    }
    private func statusIcon(_ status: String) -> String {
        switch status {
        case "confirmed":       return "checkmark.circle.fill"
        case "pending_payment": return "exclamationmark.triangle.fill"
        case "waitlist":        return "clock.fill"
        default:                return "questionmark.circle"
        }
    }
    private func statusLabel(_ status: String) -> String {
        switch status {
        case "confirmed":       return "CONFERMATA"
        case "pending_payment": return "DA PAGARE"
        case "waitlist":        return "LISTA ATTESA"
        default:                return status.uppercased()
        }
    }
}
