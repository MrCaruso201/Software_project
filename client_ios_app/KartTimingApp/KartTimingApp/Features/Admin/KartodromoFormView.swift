import SwiftUI

struct KartodromoFormView: View {
    @Environment(\.dismiss) var dismiss
    let server: DiscoveredServer
    let authState: AuthState
    let viewModel: KartodromoViewModel

    // Se `editingKartodromo` è nil, siamo in modalità Creazione.
    var editingKartodromo: Kartodromo?

    @State private var nome: String = ""
    @State private var luogo: String = ""
    @State private var url: String = ""
    @State private var sitoWeb: String = ""
    @State private var attivo: Bool = true

    @State private var isSaving = false
    @State private var errorMessage: String? = nil

    var isFormValid: Bool {
        !nome.trimmingCharacters(in: .whitespaces).isEmpty &&
        !url.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Obbligatori ─────────────────────────────────────────────
                Section(header: Text("Informazioni Obbligatorie").foregroundColor(.primary)) {
                    HStack {
                        Text("Nome")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        TextField("Es. Kartodromo di Lonato", text: $nome)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("URL Timing")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        TextField("https://...", text: $url)
                            .foregroundColor(.primary)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                }

                // ── Opzionali ────────────────────────────────────────────────
                Section(header: Text("Informazioni Aggiuntive").foregroundColor(.primary)) {
                    HStack {
                        Text("Luogo")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        TextField("Es. Lonato del Garda (BS)", text: $luogo)
                            .foregroundColor(.primary)
                    }
                    HStack {
                        Text("Sito Web")
                            .foregroundColor(.secondary)
                            .frame(width: 80, alignment: .leading)
                        TextField("", text: $sitoWeb, prompt: Text("https://...").foregroundColor(.primary))
                            .foregroundColor(.primary)
                            .keyboardType(.URL)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    Toggle(isOn: $attivo) {
                        Text("Circuito attivo")
                            .foregroundColor(.primary)
                    }
                    .tint(.orange)
                }

                // ── Errore ──────────────────────────────────────────────────
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(editingKartodromo == nil ? "Nuovo Circuito" : "Modifica Circuito")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(errorMessage == nil ? "Annulla" : "Chiudi") { dismiss() }
                        .foregroundColor(.kartForeground)
                        .tint(.kartForeground)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Salva") { save() }
                            .disabled(!isFormValid)
                            .foregroundColor(isFormValid ? .orange : .gray)
                    }
                }
            }
            .onAppear {
                if let k = editingKartodromo {
                    nome = k.nome
                    luogo = k.luogo
                    url = k.url
                    sitoWeb = k.sitoWeb
                    attivo = k.attivo
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil

        let data: [String: Any] = [
            "nome": nome.trimmingCharacters(in: .whitespaces),
            "luogo": luogo.trimmingCharacters(in: .whitespaces),
            "url": url.trimmingCharacters(in: .whitespaces),
            "sito_web": sitoWeb.trimmingCharacters(in: .whitespaces),
            "attivo": attivo
        ]

        if let k = editingKartodromo {
            viewModel.update(
                serverURL: server.httpURL,
                kartodromoId: k.id,
                data: data,
                token: authState.currentToken
            ) { success in
                isSaving = false
                if success {
                    dismiss()
                } else {
                    errorMessage = viewModel.errorMessage ?? "Errore durante il salvataggio."
                    // L'errore riguarda il form: la lista deve restare disponibile alla chiusura.
                    viewModel.errorMessage = nil
                }
            }
        } else {
            viewModel.create(
                serverURL: server.httpURL,
                data: data,
                token: authState.currentToken
            ) { success in
                isSaving = false
                if success { dismiss() } else { errorMessage = "Errore durante la creazione." }
            }
        }
    }
}
