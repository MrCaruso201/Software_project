import SwiftUI

struct EventRegistrationSheetView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent
    
    @Environment(\.dismiss) var dismiss
    
    @State private var isRegistering = false
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header info
                        VStack(alignment: .leading, spacing: 8) {
                            Text(event.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            HStack(spacing: 8) {
                                Image(systemName: "calendar")
                                    .foregroundColor(.kartAccent)
                                Text(event.formattedDate)
                                    .foregroundColor(.kartDim)
                            }
                            
                            HStack(spacing: 8) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.kartAccent)
                                Text(event.location)
                                    .foregroundColor(.kartDim)
                            }
                        }
                        .padding(.top, 10)
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        // Event details
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Dettagli Evento")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            if let cost = event.registrationCost {
                                detailRow(label: "Prezzo di iscrizione", value: "€ \(String(format: "%.2f", cost))")
                            } else {
                                detailRow(label: "Prezzo di iscrizione", value: "Gratuito")
                            }
                            
                            if let weight = event.weightLimit {
                                detailRow(label: "Peso minimo", value: "\(String(format: "%.1f", weight)) kg")
                            }
                            
                            if let maxPart = event.maxParticipants {
                                detailRow(label: "Partecipanti massimi", value: "\(maxPart)")
                            }
                        }
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        Text("Cliccando su Conferma Iscrizione, ti registrerai ufficialmente all'evento.")
                            .font(.footnote)
                            .foregroundColor(.kartDim)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 10)
                        
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.kartRed)
                                .font(.footnote)
                                .padding(.top, 5)
                        }
                        
                        Spacer(minLength: 30)
                        
                        Button {
                            performRegistration()
                        } label: {
                            HStack {
                                if isRegistering {
                                    ProgressView().tint(.black)
                                        .padding(.trailing, 5)
                                }
                                Text("Conferma Iscrizione")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.kartAccent)
                            .foregroundColor(.black)
                            .cornerRadius(10)
                        }
                        .disabled(isRegistering)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Iscrizione Evento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") {
                        dismiss()
                    }
                    .foregroundColor(.kartAccent)
                }
            }
        }
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.kartDim)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.medium)
        }
    }
    
    private func performRegistration() {
        guard let token = authState.currentToken else {
            errorMessage = "Devi essere loggato per iscriverti."
            return
        }
        
        isRegistering = true
        errorMessage = nil
        
        viewModel.registerToEvent(serverURL: server.httpURL, eventId: event.id, token: token) { success, errorMsg in
            isRegistering = false
            if success {
                dismiss()
            } else {
                errorMessage = errorMsg ?? "Errore sconosciuto."
            }
        }
    }
}
