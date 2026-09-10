import SwiftUI

struct AdminReleaseFormSheetView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let server: DiscoveredServer
    @ObservedObject var viewModel: EventiViewModel
    let event: RaceEvent
    
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) var dismiss
    
    @State private var releaseText: String = ""
    @State private var isSaving = false
    @State private var saveMessage: String? = nil
    
    @State private var previewPDFData: Data? = nil
    @State private var showPreviewSheet: Bool = false
    @State private var isPreviewing = false
    @State private var signedReleases: [SignedReleaseResponse] = []
    @State private var isLoadingReleases = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        
                        // ── Text Editor per il testo della liberatoria
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Testo Liberatoria")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.kartAccent)
                            
                            TextEditor(text: $releaseText)
                                .frame(height: 150)
                                .padding(4)
                                .background(Color.kartForeground.opacity(0.1))
                                .cornerRadius(8)
                                .foregroundColor(.kartForeground)
                                .scrollContentBackground(.hidden)
                            
                            HStack {
                                if let msg = saveMessage {
                                    Label(msg, systemImage: msg.contains("Errore") ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(msg.contains("Errore") ? .kartRed : .kartSuccess)
                                        .padding(8)
                                        .background(Color.kartPanel, in: RoundedRectangle(cornerRadius: 8))
                                        .transition(.opacity)
                                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: saveMessage)
                                }
                                Spacer()
                                HStack(spacing: 12) {
                                    Button(action: previewAdminRelease) {
                                        if isPreviewing {
                                            ProgressView().tint(.kartForeground)
                                        } else {
                                            Text("Anteprima")
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.kartForeground.opacity(0.1))
                                    .foregroundColor(.kartForeground)
                                    .cornerRadius(8)
                                    .disabled(isPreviewing)
                                    
                                    Button(action: saveReleaseForm) {
                                        if isSaving {
                                            ProgressView().tint(.white)
                                        } else {
                                            Text("Salva Testo")
                                                .font(.system(size: 13, weight: .bold))
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Color.kartAccent)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .disabled(isSaving)
                                }
                            }
                        }
                        .padding()
                        .background(Color.kartPanel)
                        .cornerRadius(12)
                        
                        // ── Elenco Firme
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Liberatorie Firmate (\(signedReleases.count))")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.kartAccent)
                            
                            if isLoadingReleases {
                                ProgressView().tint(.kartAccent).padding()
                            } else if signedReleases.isEmpty {
                                Text("Nessun utente ha ancora firmato la liberatoria.")
                                    .font(.system(size: 13))
                                    .foregroundColor(.kartDim)
                                    .padding(.top, 4)
                            } else {
                                ForEach(signedReleases) { release in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(release.username ?? "")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundColor(.kartForeground)
                                                
                                            let first = release.firstName ?? ""
                                            let last = release.lastName ?? ""
                                            if !first.isEmpty || !last.isEmpty {
                                                Text("\(first) \(last)")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.kartDim)
                                            }
                                        }
                                        Spacer()
                                        if let uId = release.userId {
                                            Button(action: {
                                                downloadPDF(userId: uId)
                                            }) {
                                                Image(systemName: "arrow.down.doc.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.white)
                                                    .padding(8)
                                                    .background(Color.blue)
                                                    .cornerRadius(6)
                                            }
                                            
                                            Button(action: {
                                                rejectRelease(userId: uId)
                                            }) {
                                                Image(systemName: "trash.fill")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(.white)
                                                    .padding(8)
                                                    .background(Color.red)
                                                    .cornerRadius(6)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.kartForeground.opacity(0.05))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding()
                        .background(Color.kartPanel)
                        .cornerRadius(12)
                        
                    }
                    .padding()
                }
            }
            .buttonStyle(KartPressButtonStyle())
            .sensoryFeedback(.success, trigger: saveMessage) { _, message in
                message == "Salvato con successo!"
            }
            .navigationTitle("Gestione Liberatoria")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                }
            }
        }
        .onAppear {
            releaseText = event.releaseFormText ?? ""
            loadSignedReleases()
        }
        .sheet(isPresented: $showPreviewSheet) {
            if let data = previewPDFData {
                VStack {
                    HStack {
                        Spacer()
                        Button("Chiudi") {
                            showPreviewSheet = false
                        }
                        .padding()
                        .foregroundColor(.kartAccent)
                        .font(.system(size: 16, weight: .bold))
                    }
                    PDFViewer(pdfData: data)
                }
            }
        }
    }
    
    private func saveReleaseForm() {
        guard let token = authState.currentToken else { return }
        isSaving = true
        saveMessage = nil
        
        viewModel.adminUpdateReleaseForm(serverURL: server.httpURL, eventId: event.id, token: token, text: releaseText) { success in
            isSaving = false
            if success {
                saveMessage = "Salvato con successo!"
                loadSignedReleases() // Aggiorna la vista delle firme
            } else {
                saveMessage = "Errore durante il salvataggio."
            }
        }
    }
    
    private func previewAdminRelease() {
        guard let serverURL = server.httpURL, let token = authState.currentToken else { return }
        
        isPreviewing = true
        saveMessage = nil
        
        viewModel.previewAdminReleaseForm(serverURL: serverURL, eventId: event.id, token: token, text: releaseText) { data, errorMsg in
            isPreviewing = false
            if let data = data {
                self.previewPDFData = data
                self.showPreviewSheet = true
            } else {
                self.saveMessage = errorMsg ?? "Errore durante l'anteprima"
            }
        }
    }
    
    private func loadSignedReleases() {
        guard let token = authState.currentToken else { return }
        isLoadingReleases = true
        
        viewModel.adminFetchSignedReleases(serverURL: server.httpURL, eventId: event.id, token: token) { releases in
            isLoadingReleases = false
            if let releases = releases {
                self.signedReleases = releases
            }
        }
    }
    
    private func downloadPDF(userId: Int) {
        guard let token = authState.currentToken,
              let serverURL = server.httpURL else { return }
        
        let url = serverURL.appendingPathComponent("admin/events/\(event.id)/releases/\(userId)/pdf")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "token", value: token)]
        
        if let downloadURL = comps?.url {
            UIApplication.shared.open(downloadURL)
        }
    }
    private func rejectRelease(userId: Int) {
        guard let token = authState.currentToken,
              let serverURL = server.httpURL else { return }
        
        viewModel.adminDeleteSignedRelease(serverURL: serverURL, eventId: event.id, userId: userId, token: token) { success in
            if success {
                loadSignedReleases()
            }
        }
    }
}
