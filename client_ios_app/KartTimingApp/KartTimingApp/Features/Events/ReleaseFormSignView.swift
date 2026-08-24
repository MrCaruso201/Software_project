import SwiftUI
import PencilKit

struct ReleaseFormSignView: View {
    let server: DiscoveredServer
    let event: RaceEvent
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = EventiViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    var onSignComplete: (() -> Void)? = nil
    
    @State private var canvasView = PKCanvasView()
    @State private var releaseText: String = "Caricamento in corso..."
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var codiceFiscale: String = ""
    @State private var birthDate: String = ""
    @State private var residence: String = ""
    @State private var isSigning: Bool = false
    @State private var errorMessage: String? = nil
    @State private var previousSignatureImage: UIImage? = nil
    
    var body: some View {
            VStack(spacing: 16) {
                Text("Liberatoria Evento")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top)
                
                ScrollView {
                Text(releaseText)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
            }
            .frame(maxHeight: 250)
            .background(Color.kartPanel)
            .cornerRadius(12)
            .padding(.horizontal)
            
            VStack(spacing: 12) {
                TextField("Nome", text: $firstName)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                
                TextField("Cognome", text: $lastName)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    
                TextField("Codice Fiscale", text: $codiceFiscale)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .autocapitalization(.allCharacters)
                    
                TextField("Data di Nascita (dd/mm/yyyy)", text: $birthDate)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    
                TextField("Luogo di Residenza", text: $residence)
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
            .environment(\.colorScheme, .dark)
            
            if let oldImage = previousSignatureImage {
                VStack(spacing: 12) {
                    Text("Hai già firmato la liberatoria. Clicca sotto per sostituirla.")
                        .font(.system(size: 13))
                        .foregroundColor(.kartDim)
                    
                    Image(uiImage: oldImage)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 180)
                        .background(Color.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                    
                    Button(action: {
                        previousSignatureImage = nil
                    }) {
                        Text("Cancella e Rifirma")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 16)
                            .background(Color.kartRed)
                            .cornerRadius(8)
                    }
                }
            } else {
                HStack {
                    Text("Firma qui sotto:")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.kartAccent)
                    Spacer()
                    Button(action: {
                        canvasView.drawing = PKDrawing()
                    }) {
                        Text("Pulisci")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.kartRed)
                    }
                }
                .padding(.horizontal)
                
                ZStack(alignment: .topTrailing) {
                    SignaturePadView(canvasView: $canvasView)
                        .frame(height: 180)
                        .background(Color.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.kartRed)
                    .font(.footnote)
                    .padding(.horizontal)
            }
            
            Spacer()
                
                Button(action: submitSignature) {
                    if isSigning {
                        ProgressView().tint(.black)
                    } else {
                        Text("Conferma e Invia")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 14)
                .background(Color.kartAccent)
                .foregroundColor(.black)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 16)
                .disabled(isSigning)
            }
            .background(Color.kartBG.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadReleaseText()
            loadMyReleaseForm()
        }
    }
    
    private func loadMyReleaseForm() {
        viewModel.fetchMyReleaseForm(serverURL: server.httpURL, eventId: event.id, token: authState.currentToken) { response in
            if let response = response {
                self.firstName = response.firstName ?? ""
                self.lastName = response.lastName ?? ""
                self.codiceFiscale = response.codiceFiscale ?? ""
                if let bDateStr = response.birthDate {
                    self.birthDate = bDateStr
                }
                self.residence = response.residence ?? ""
                
                if let b64 = response.signatureBase64,
                   let data = Data(base64Encoded: b64),
                   let img = UIImage(data: data) {
                    self.previousSignatureImage = img
                }
            }
        }
    }
    
    private func loadReleaseText() {
        if let text = event.releaseFormText, !text.isEmpty {
            self.releaseText = text
        } else {
            viewModel.fetchReleaseFormText(serverURL: server.httpURL, eventId: event.id) { text in
                if let text = text {
                    self.releaseText = text
                } else {
                    self.releaseText = "Nessun testo disponibile per questa liberatoria."
                }
            }
        }
    }
    
    private func submitSignature() {
        if firstName.trimmingCharacters(in: .whitespaces).isEmpty || 
           lastName.trimmingCharacters(in: .whitespaces).isEmpty ||
           codiceFiscale.trimmingCharacters(in: .whitespaces).isEmpty ||
           birthDate.trimmingCharacters(in: .whitespaces).isEmpty ||
           residence.trimmingCharacters(in: .whitespaces).isEmpty {
            self.errorMessage = "Compila tutti i campi richiesti."
            return
        }
        
        if previousSignatureImage == nil && canvasView.drawing.bounds.isEmpty {
            self.errorMessage = "Devi firmare la liberatoria."
            return
        }
        
        let base64String: String
        
        if let oldImage = previousSignatureImage, let data = oldImage.pngData() {
            base64String = data.base64EncodedString()
        } else {
            let drawing = canvasView.drawing
            let uiRect = canvasView.bounds.isEmpty ? CGRect(x: 0, y: 0, width: 300, height: 150) : canvasView.bounds
            
            let image = drawing.image(from: uiRect, scale: 1.0)
            guard let imageData = image.pngData() else {
                self.errorMessage = "Errore durante la codifica della firma."
                return
            }
            base64String = imageData.base64EncodedString()
        }
        
        self.isSigning = true
        self.errorMessage = nil
        
        viewModel.signReleaseForm(serverURL: server.httpURL, eventId: event.id, token: authState.currentToken, firstName: firstName, lastName: lastName, codiceFiscale: codiceFiscale, birthDate: birthDate, residence: residence, signatureBase64: base64String) { success, msg in
            self.isSigning = false
            if success {
                self.onSignComplete?()
                self.presentationMode.wrappedValue.dismiss()
            } else {
                self.errorMessage = msg ?? "Errore sconosciuto"
            }
        }
    }
}
