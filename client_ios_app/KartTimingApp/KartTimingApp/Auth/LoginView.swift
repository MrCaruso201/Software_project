import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var appEnv: AppEnvironment
    @State private var isLoginTab = true

    // Campi
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    // Stato UI
    @State private var isLoadingLogin = false
    @State private var isLoadingGuest = false
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.kartBG.ignoresSafeArea()

                // Contenuto principale
                VStack(spacing: 32) {
                    // Logo o titolo
                    VStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 60))
                            .foregroundColor(.kartAccent)
                        Text("Race Manager")
                            .font(.system(size: 28, weight: .heavy, design: .default))
                            .foregroundColor(.kartForeground)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 20)

                    // Tab Switcher
                    HStack(spacing: 0) {
                        TabButton(title: "Accedi", isSelected: isLoginTab) {
                            withAnimation { isLoginTab = true; errorMessage = nil }
                        }
                        TabButton(title: "Registrati", isSelected: !isLoginTab) {
                            withAnimation { isLoginTab = false; errorMessage = nil }
                        }
                    }
                    .background(Color.kartPanel)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)

                    // Campi di testo
                    VStack(spacing: 16) {
                        CustomTextField(placeholder: isLoginTab ? "Username o Email" : "Username", text: $username, icon: "person")

                        if !isLoginTab {
                            CustomTextField(placeholder: "Email", text: $email, icon: "envelope")
                                .keyboardType(.emailAddress)
                        }

                        CustomSecureField(placeholder: "Password", text: $password, icon: "lock")
                            .submitLabel(isLoginTab ? .go : .done)
                            .onSubmit {
                                if isLoginTab { submit() }
                            }
                    }
                    .padding(.horizontal, 30)

                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.kartRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }

                    // Pulsante d'azione
                    Button(action: submit) {
                        HStack {
                            if isLoadingLogin {
                                ProgressView().tint(.white)
                            } else {
                                Text(isLoginTab ? "Accedi" : "Crea account")
                                    .font(.title3.weight(.bold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.kartAccent)
                        .cornerRadius(12)
                        .shadow(color: Color.kartAccent.opacity(0.3), radius: 10, x: 0, y: 5)
                    }
                    .disabled(isLoadingLogin || isLoadingGuest || username.isEmpty || password.isEmpty || (!isLoginTab && email.isEmpty))
                    .opacity((isLoadingLogin || username.isEmpty || password.isEmpty || (!isLoginTab && email.isEmpty)) ? 0.6 : 1.0)
                    .padding(.horizontal, 30)

                    // ── Pulsante "Live Timing senza accesso" flottante ──────
                    Button(action: loginAsGuest) {
                        HStack(spacing: 10) {
                            if isLoadingGuest {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: "flag.checkered")
                                    .font(.system(size: 17, weight: .semibold))
                                Text("Live Timing senza accesso")
                                    .font(.title3.weight(.bold))
                            }
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.82, blue: 0.0),
                                         Color(red: 1.0, green: 0.65, blue: 0.0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(12)
                        .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.45), radius: 10, x: 0, y: 5)
                    }
                    .disabled(isLoadingGuest || isLoadingLogin)
                    .padding(.horizontal, 30)

                    // ── DEV MODE ─────────────────────────────────────────────
                    DevModeToggle(isEnabled: $appEnv.devModeEnabled)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 16)

                    Spacer()
                }
            }
        }
    }

    private func submit() {
        guard !isLoadingLogin, !isLoadingGuest,
              !username.isEmpty, !password.isEmpty,
              isLoginTab || !email.isEmpty else { return }
        isLoadingLogin = true
        errorMessage = nil

        let requestTask = Task {
            do {
                if isLoginTab {
                    let tokens = try await AuthService.login(username: username, password: password)
                    authState.setLoginData(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
                } else {
                    try await AuthService.register(username: username, email: email, password: password)
                    isLoginTab = true
                    errorMessage = "Registrazione completata. Ora puoi accedere."
                }
            } catch let err as AuthError {
                errorMessage = err.localizedDescription
            } catch {
                errorMessage = "Si è verificato un errore imprevisto."
            }
            isLoadingLogin = false
        }

        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !requestTask.isCancelled && isLoadingLogin {
                requestTask.cancel()
                await MainActor.run {
                    isLoadingLogin = false
                    errorMessage = "Connessione scaduta. Riprova."
                }
            }
        }
    }

    private func loginAsGuest() {
        isLoadingGuest = true
        errorMessage = nil

        let requestTask = Task {
            do {
                let tokens = try await AuthService.login(username: "viewer", password: "viewer")
                authState.setLoginData(
                    accessToken: tokens.accessToken,
                    refreshToken: tokens.refreshToken,
                    guestSession: true
                )
            } catch let err as AuthError {
                errorMessage = err.localizedDescription
            } catch {
                errorMessage = "Impossibile accedere al Live Timing."
            }
            isLoadingGuest = false
        }

        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if !requestTask.isCancelled && isLoadingGuest {
                requestTask.cancel()
                await MainActor.run {
                    isLoadingGuest = false
                    errorMessage = "Connessione scaduta. Riprova."
                }
            }
        }
    }
}


// MARK: - Componenti UI

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isSelected ? .white : .kartDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color.kartAccent.opacity(0.8) : Color.clear)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct CustomTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.kartDim)
                .frame(width: 20)
            TextField("", text: $text)
                .focused($isFocused)
                .foregroundColor(.kartForeground)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder).foregroundColor(.kartDim)
                }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.kartPanel)
        .cornerRadius(12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { isFocused = true }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1))
    }
}

struct CustomSecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.kartDim)
                .frame(width: 20)
            SecureField("", text: $text)
                .focused($isFocused)
                .foregroundColor(.kartForeground)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder).foregroundColor(.kartDim)
                }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.kartPanel)
        .cornerRadius(12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { isFocused = true }
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1))
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}


// MARK: - DEV MODE Toggle

struct DevModeToggle: View {
    @Binding var isEnabled: Bool
    @State private var showingServerSelection = false
    @StateObject private var browser = ServerBrowser()

    var body: some View {
        VStack(spacing: 8) {
            // Toggle row
            HStack(spacing: 12) {
                // Icona
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isEnabled
                              ? Color.orange.opacity(0.25)
                              : Color.kartPanel)
                        .frame(width: 36, height: 36)
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isEnabled ? .orange : .kartDim)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("DEV MODE")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(isEnabled ? .orange : .kartDim)
                    Text("Connessione al server locale")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.kartDim)
                }

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .tint(.orange)
                    .onChange(of: isEnabled) { oldValue, newValue in
                        if newValue {
                            showingServerSelection = true
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.kartPanel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isEnabled ? Color.orange.opacity(0.5) : Color.kartForeground.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isEnabled)

            // Banner host locale (visibile solo quando attivo)
            if isEnabled {
                Button(action: { showingServerSelection = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "network")
                            .font(.system(size: 11))
                        let host = AppEnvironment.shared.selectedLocalHost ?? "Nessuno"
                        let port = AppEnvironment.shared.selectedLocalPort ?? 8000
                        Text("\(host):\(port)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.kartWarning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(8)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isEnabled)
        .sheet(isPresented: $showingServerSelection) {
            ServerSelectionView(browser: browser, isPresented: $showingServerSelection, isEnabled: $isEnabled)
        }
    }
}


// MARK: - Server Selection View

struct ServerSelectionView: View {
    @ObservedObject var browser: ServerBrowser
    @Binding var isPresented: Bool
    @Binding var isEnabled: Bool
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Server Locali (Bonjour)").foregroundColor(.kartDim)) {
                    if browser.discoveredServers.isEmpty {
                        HStack {
                            ProgressView().padding(.trailing, 8)
                            Text("Ricerca in corso...")
                                .foregroundColor(.kartDim)
                        }
                    } else {
                        ForEach(browser.discoveredServers) { server in
                            Button(action: {
                                AppEnvironment.shared.selectedLocalHost = server.host
                                AppEnvironment.shared.selectedLocalPort = server.port
                                isEnabled = true
                                isPresented = false
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(server.name)
                                            .font(.headline)
                                            .foregroundColor(.kartForeground)
                                        Text("\(server.host):\(server.port)")
                                            .font(.caption)
                                            .foregroundColor(.kartDim)
                                            .fontDesign(.monospaced)
                                    }
                                    Spacer()
                                    if AppEnvironment.shared.selectedLocalHost == server.host {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.kartWarning)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listRowBackground(Color.kartPanel)
            }
            .scrollContentBackground(.hidden)
            .background(Color.kartBG.ignoresSafeArea())
            .navigationTitle("Seleziona Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Annulla") {
                        isEnabled = false
                        isPresented = false
                    }
                    .foregroundColor(.kartWarning)
                }
            }
        }
        .onAppear {
            browser.startBrowsing()
        }
        .onDisappear {
            browser.stopBrowsing()
        }
    }
}
