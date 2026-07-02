import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authState: AuthState
    @State private var isLoginTab = true

    // Campi
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    // Stato UI
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 32) {
                // Logo o titolo
                VStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 60))
                        .foregroundColor(.kartAccent)
                    Text("Race Manager")
                        .font(.system(size: 28, weight: .heavy, design: .default))
                        .foregroundColor(.white)
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
                    CustomTextField(placeholder: "Username", text: $username, icon: "person")
                    
                    if !isLoginTab {
                        CustomTextField(placeholder: "Email", text: $email, icon: "envelope")
                            .keyboardType(.emailAddress)
                    }

                    CustomSecureField(placeholder: "Password", text: $password, icon: "lock")
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
                        if isLoading {
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
                .disabled(isLoading || username.isEmpty || password.isEmpty || (!isLoginTab && email.isEmpty))
                .opacity((isLoading || username.isEmpty || password.isEmpty || (!isLoginTab && email.isEmpty)) ? 0.6 : 1.0)
                .padding(.horizontal, 30)

                Spacer()
            }
        }
    }

    private func submit() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                if isLoginTab {
                    let tokens = try await AuthService.login(username: username, password: password)
                    authState.setLoginData(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken)
                } else {
                    try await AuthService.register(username: username, email: email, password: password)
                    // Dopo registrazione con successo, passa automaticamente al tab di login e compila campi
                    isLoginTab = true
                    errorMessage = "Registrazione completata. Ora puoi accedere."
                }
            } catch let err as AuthError {
                errorMessage = err.localizedDescription
            } catch {
                errorMessage = "Si è verificato un errore imprevisto."
            }
            isLoading = false
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

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.kartDim)
                .frame(width: 20)
            TextField("", text: $text)
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder).foregroundColor(.kartDim)
                }
        }
        .padding()
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }
}

struct CustomSecureField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.kartDim)
                .frame(width: 20)
            SecureField("", text: $text)
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .placeholder(when: text.isEmpty) {
                    Text(placeholder).foregroundColor(.kartDim)
                }
        }
        .padding()
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
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
