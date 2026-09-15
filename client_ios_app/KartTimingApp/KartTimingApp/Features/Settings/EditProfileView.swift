import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

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
    @State private var showDeleteConfirmation = false

    private var resolvedAvatarURL: URL? {
        guard let token = authState.currentToken else { return nil }
        return authState.avatarURL(path: profilePictureURL, serverURL: appEnv.server(token: token).httpURL)
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
                                        Circle().stroke(Color.kartBorder(opacity: 0.08), lineWidth: 1)
                                    )
                                
                                if isUploadingAvatar {
                                    ProgressView().tint(.kartForeground)
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
                                            .foregroundColor(.white)
                                    )
                                    .offset(x: 28, y: 28)
                            }
                        }
                        .disabled(isUploadingAvatar)
                        .onChange(of: selectedItem) { _, newItem in
                            Task {
                                guard let newItem else { return }
                                isUploadingAvatar = true
                                defer { isUploadingAvatar = false }
                                do {
                                    guard let data = try await newItem.loadTransferable(type: Data.self) else {
                                        throw URLError(.cannotDecodeContentData)
                                    }
                                    let prepared = try await AvatarPreparation.jpeg(from: data)
                                    try await uploadAvatar(data: prepared)
                                    if let image = UIImage(data: prepared) { avatarImage = Image(uiImage: image) }
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }
                        .padding(.top, 32)

                        // ── Campi ────────────────────────────────────────────
                        VStack(spacing: 14) {
                            
                            // Campi sola lettura (Username e Email)
                            disabledField(title: "Username", icon: "person", text: username)
                            disabledField(title: "Email", icon: "envelope", text: email)
                            
                            Divider().background(Color.kartBorder(opacity: 0.2)).padding(.vertical, 8)
                            
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
                                        .tint(.kartDim)
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 15, weight: .bold))
                                }
                                Text(isLoading ? "Salvataggio…" : "Salva Profilo")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(!isLoading ? .white : .kartDim)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(!isLoading ? Color.kartGreen : Color.kartPanel)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.kartBorder(opacity: 0.08), lineWidth: 1)
                            )
                        }
                        .disabled(isLoading)
                        .padding(.horizontal, 24)
                        
                        // ── Bottone Elimina Account ──────────────────────────
                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 15, weight: .bold))
                                Text("ELIMINA ACCOUNT")
                                    .font(.system(size: 16, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.kartRed)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.kartBorder(opacity: 0.08), lineWidth: 1)
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
        .alert("Elimina Account", isPresented: $showDeleteConfirmation) {
            Button("Annulla", role: .cancel) { }.tint(.kartForeground)
            Button("Elimina", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("Sei sicuro di voler eliminare definitivamente il tuo account? Questa azione è irreversibile.")
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
                    .foregroundColor(.kartForeground)
            }
            .padding(14)
            .background(Color.kartPanel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Logic
    
    private func deleteAccount() {
        guard let token = authState.currentToken else { return }
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await AuthService.deleteAccount(token: token)
                await MainActor.run {
                    isLoading = false
                    authState.logout()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

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
    private func uploadAvatar(data: Data) async throws {
        guard let token = authState.currentToken else { throw URLError(.userAuthenticationRequired) }
        let userID = authState.currentUser?.id
        errorMessage = nil
        let path = try await AuthService.uploadAvatar(imageData: data, token: token)
        guard authState.currentUser?.id == userID, authState.isLoggedIn else { return }
        profilePictureURL = path
        authState.didUploadAvatar(path: path)
    }
}

nonisolated private enum AvatarPreparation {
    @concurrent
    static func jpeg(from data: Data) async throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        // Riduce prima la qualità, poi le dimensioni per rispettare il budget.
        var thumbnail = image
        while true {
            for quality in [0.75, 0.6, 0.45] {
                let output = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw URLError(.cannotCreateFile)
                }
                CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw URLError(.cannotCreateFile) }
                if output.length <= 100 * 1024 { return output as Data }
            }
            let size = max(thumbnail.width, thumbnail.height) / 2
            guard size >= 64,
                  let smaller = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: size,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw URLError(.cannotCreateFile) }
            thumbnail = smaller
        }
    }
}
