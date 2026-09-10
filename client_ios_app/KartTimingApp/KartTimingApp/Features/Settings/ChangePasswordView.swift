import SwiftUI

struct ChangePasswordView: View {
    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var oldPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""

    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSuccess: Bool = false

    // Validazione in tempo reale
    private var passwordsMatch: Bool { newPassword == confirmPassword }
    private var newPasswordLongEnough: Bool { newPassword.count >= 3 }
    private var formIsValid: Bool {
        !oldPassword.isEmpty && newPasswordLongEnough && passwordsMatch
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // ── Icona decorativa ─────────────────────────────────
                    ZStack {
                        Circle()
                            .fill(Color.kartPanel)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle().stroke(Color.kartBorder(opacity: 0.08), lineWidth: 1)
                            )
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundColor(.kartAccent)
                    }
                    .padding(.top, 32)

                    // ── Campi ────────────────────────────────────────────
                    VStack(spacing: 14) {
                        passwordField(
                            title: "Vecchia password",
                            icon: "lock",
                            text: $oldPassword,
                            hint: nil
                        )

                        passwordField(
                            title: "Nuova password",
                            icon: "lock.open",
                            text: $newPassword,
                            hint: newPassword.isEmpty ? nil :
                                (!newPasswordLongEnough ? "Minimo 3 caratteri" : nil)
                        )

                        passwordField(
                            title: "Conferma nuova password",
                            icon: "lock.open",
                            text: $confirmPassword,
                            hint: confirmPassword.isEmpty ? nil :
                                (!passwordsMatch ? "Le password non coincidono" : nil)
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
                            Text(isLoading ? "Salvataggio…" : "Aggiorna password")
                                .font(.system(size: 16, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            formIsValid && !isLoading
                                ? LinearGradient(
                                    colors: [Color(red: 1.0, green: 0.82, blue: 0.0),
                                             Color(red: 1.0, green: 0.65, blue: 0.0)],
                                    startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(
                                    colors: [Color.kartPanel, Color.kartPanel],
                                    startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.kartBorder(opacity: 0.08), lineWidth: 1)
                        )
                    }
                    .disabled(!formIsValid || isLoading)
                    .padding(.horizontal, 24)

                    Spacer(minLength: 32)
                }
            }
        }
        .navigationTitle("Cambia password")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .alert("Password aggiornata", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("La tua password è stata modificata con successo.")
        }
        .animation(.easeInOut(duration: 0.2), value: errorMessage)
    }

    // MARK: - Campo password riutilizzabile

    @ViewBuilder
    private func passwordField(
        title: String,
        icon: String,
        text: Binding<String>,
        hint: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundColor(.kartDim)

            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(.kartDim)
                    .frame(width: 18)
                SecureField("••••••••", text: text)
                    .foregroundColor(.kartForeground)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(14)
            .background(Color.kartPanel)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        hint != nil ? Color.red.opacity(0.6) : Color.kartForeground.opacity(0.1),
                        lineWidth: 1
                    )
            )

            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hint)
    }

    // MARK: - Logic

    private func submit() {
        guard let token = authState.currentToken else { return }
        errorMessage = nil
        isLoading = true

        Task {
            do {
                try await AuthService.changePassword(
                    oldPassword: oldPassword,
                    newPassword: newPassword,
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
}
