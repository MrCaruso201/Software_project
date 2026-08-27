import SwiftUI
import PhotosUI

struct EditProfileView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var appEnv: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var email: String = ""
    @State private var username: String = ""
    @State private var profilePictureURL: String? = nil

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var avatarImage: Image? = nil
    @State private var isUploadingAvatar: Bool = false

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSuccess: Bool = false
    @State private var isFetching: Bool = true

    private var resolvedAvatarURL: URL? {
        guard let profilePictureURL = profilePictureURL,
              let token = authState.currentToken else { return nil }
        return URL(string: appEnv.server(token: token).httpURL?.absoluteString.replacingOccurrences(of: "/api", with: "") ?? "")?.appendingPathComponent(String(profilePictureURL.dropFirst()))
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if isFetching {
                ProgressView().tint(.kartAccent).scaleEffect(1.3)
            } else {
                ScrollView {
                    VStack(spacing: 24) {

                        // ── Icona decorativa / Upload Avatar ─────────────────
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .fill(Color.kartPanel)
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )
                                
                                if isUploadingAvatar {
                                    ProgressView().tint(.white)
                                } else if let avatarImage {
                                    avatarImage
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                } else if let url = resolvedAvatarURL {
                                    AsyncImage(url: url) { phase in
                                        if let img = phase.image {
                                            img.resizable()
                                                .scaledToFill()
                                                .frame(width: 80, height: 80)
                                                .clipShape(Circle())
                                        } else if phase.error != nil {
                                            Image(systemName: "person.crop.circle.fill")
                                                .font(.system(size: 38, weight: .semibold))
                                                .foregroundColor(.kartAccent)
                                        } else {
                                            ProgressView()
                                        }
                                    }
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 38, weight: .semibold))
                                        .foregroundColor(.kartAccent)
                                }
                                
                                // Badge camera
                                Circle()
                                    .fill(Color.kartAccent)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.black)
                                    )
                                    .offset(x: 28, y: 28)
                            }
                        }
                        .disabled(isUploadingAvatar)
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    if let uiImage = UIImage(data: data) {
                                        avatarImage = Image(uiImage: uiImage)
                                    }
                                    await uploadAvatar(data: data)
                                }
                            }
                        }
                        .padding(.top, 32)

                        // ── Campi ────────────────────────────────────────────
                        VStack(spacing: 14) {
                            
                            // Campi sola lettura (Username e Email)
                            disabledField(title: "Username", icon: "person", text: username)
                            disabledField(title: "Email", icon: "envelope", text: email)
                            
                            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 8)
                            
                            // Campi modificabili
                            editableField(
                                title: "Nome",
                                icon: "textformat",
                                text: $firstName
                            )

                            editableField(
                                title: "Cognome",
                                icon: "textformat",
                                text: $lastName
                            )
                        }
                        .padding(.horizontal, 24)

                        // ── Feedback errore ──────────────────────────────────
                        if let err = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text(err)
                                    .font(.footnote.weight(.medium))
                            }
                            .foregroundColor(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(10)
                            .padding(.horizontal, 24)
                            .transition(.opacity)
                        }

                        // ── Bottone conferma ─────────────────────────────────
                        Button {
                            submit()
                        } label: {
                            HStack(spacing: 10) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.black)
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                Text(isLoading ? "Salvataggio…" : "Salva Profilo")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                !isLoading
                                    ? LinearGradient(
                                        colors: [Color.kartAccent,
                                                 Color(red: 1.0, green: 0.65, blue: 0.0)],
                                        startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(
                                        colors: [Color.kartPanel, Color.kartPanel],
                                        startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .disabled(isLoading)
                        .padding(.horizontal, 24)

                        Spacer(minLength: 32)
                    }
                }
            }
        }
        .navigationTitle("Informazioni Personali")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            fetchProfile()
        }
        .alert("Profilo aggiornato", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Le tue informazioni sono state salvate con successo.")
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // MARK: - Campi riutilizzabili

    @ViewBuilder
    private func disabledField(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundColor(.kartDim)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.kartDim)
                    .frame(width: 18)
                Text(text)
                    .foregroundColor(.kartDim)
                Spacer()
            }
            .padding(14)
            .background(Color.kartPanel.opacity(0.5))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private func editableField(title: String, icon: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundColor(.kartDim)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.kartDim)
                    .frame(width: 18)
                TextField("Inserisci \(title.lowercased())", text: text)
                    .foregroundColor(.white)
            }
            .padding(14)
            .background(Color.kartPanel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Logic

    private func fetchProfile() {
        guard let token = authState.currentToken,
              let url = appEnv.server(token: token).httpURL?.appendingPathComponent("auth/me") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        NetworkService.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.isFetching = false
                if let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self.username = json["username"] as? String ?? ""
                    self.email = json["email"] as? String ?? ""
                    self.firstName = json["first_name"] as? String ?? ""
                    self.lastName = json["last_name"] as? String ?? ""
                    self.profilePictureURL = json["profile_picture_url"] as? String
                }
            }
        }.resume()
    }

    private func submit() {
        guard let token = authState.currentToken else { return }
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await AuthService.updateProfile(
                    firstName: firstName,
                    lastName: lastName,
                    token: token
                )
                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    private func uploadAvatar(data: Data) async {
        guard let token = authState.currentToken else { return }
        await MainActor.run { isUploadingAvatar = true }
        
        do {
            try await AuthService.uploadAvatar(imageData: data, token: token)
            await MainActor.run { isUploadingAvatar = false }
        } catch {
            await MainActor.run {
                isUploadingAvatar = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
