import SwiftUI

struct AdminEventRegistrationsView: View {
    let server: DiscoveredServer
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent
    
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    
    @State private var registrations: [EventRegistrationWithUserResponse] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                if isLoading {
                    ProgressView().tint(.kartAccent).scaleEffect(1.3)
                } else if registrations.isEmpty {
                    VStack {
                        Image(systemName: "person.3")
                            .font(.system(size: 40))
                            .foregroundColor(.kartDim)
                        Text("Nessun iscritto")
                            .foregroundColor(.kartDim)
                            .padding(.top, 8)
                    }
                } else {
                    List {
                        ForEach(registrations) { reg in
                            registrationRow(reg)
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Iscrizioni: \(event.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
            .onAppear {
                loadRegistrations()
            }
        }
    }
    
    private func registrationRow(_ reg: EventRegistrationWithUserResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(reg.username)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                
                if reg.status == "confirmed" {
                    Text("Confermata")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                } else {
                    Text("Attesa Pagamento")
                        .font(.caption).bold()
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
            }
            
            Text(reg.email)
                .font(.footnote)
                .foregroundColor(.kartDim)
            
            HStack(spacing: 12) {
                if reg.status != "confirmed" {
                    Button {
                        confirmReg(userId: reg.userId)
                    } label: {
                        Text("Conferma Pagamento")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Button {
                    deleteReg(userId: reg.userId)
                } label: {
                    Text("Rimuovi")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.kartRed)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.kartPanel)
    }
    
    private func loadRegistrations() {
        guard let token = authState.currentToken else { return }
        isLoading = true
        viewModel.fetchEventRegistrations(serverURL: server.httpURL, eventId: event.id, token: token) { loadedRegs in
            self.isLoading = false
            if let loadedRegs = loadedRegs {
                self.registrations = loadedRegs
            }
        }
    }
    
    private func confirmReg(userId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.confirmRegistration(serverURL: server.httpURL, eventId: event.id, userId: userId, token: token) { success in
            if success {
                loadRegistrations()
            }
        }
    }
    
    private func deleteReg(userId: Int) {
        guard let token = authState.currentToken else { return }
        viewModel.adminDeleteRegistration(serverURL: server.httpURL, eventId: event.id, userId: userId, token: token) { success in
            if success {
                loadRegistrations()
            }
        }
    }
}
