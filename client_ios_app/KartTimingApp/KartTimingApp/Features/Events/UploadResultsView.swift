import SwiftUI
import UniformTypeIdentifiers

/// View per l'upload della classifica gara (solo admin, gara terminata).
/// Permette di scegliere un CSV dal Files e inviarlo al server.
/// Endpoint: POST /events/{id}/results/import_csv
struct UploadResultsView: View {
    let server: DiscoveredServer
    let event: RaceEvent

    @EnvironmentObject var authState: AuthState
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var selectedFileURL: URL? = nil
    @State private var selectedFileName: String? = nil
    @State private var isUploading = false
    @State private var resultMessage: String? = nil
    @State private var errorMessage: String? = nil
    @State private var importedCount: Int? = nil
    @State private var importErrors: [String] = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {

                        // ── Info formato CSV ──────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundColor(.kartAccent)
                                    .font(.system(size: 12, weight: .bold))
                                Text("FORMATO CSV ATTESO")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.kartAccent)
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 12)

                            if event.isTeamEvent {
                                csvFormatRow("Posizione, Pilota, Squadra, Miglior Giro, Gap, Giri, username")
                                csvFormatRow("1, Mario Rossi, Team Alpha, 1:05.234, +0.0, 12, mario_r")
                                csvFormatRow("1, Luca Bianchi, Team Alpha, 1:05.234, +0.0, 12, luca_b")
                                csvFormatRow("2, Anna Verdi, Team Beta, 1:06.100, +0.8, 12,")
                            } else {
                                csvFormatRow("Posizione, Pilota, Miglior Giro, Gap, Giri, username")
                                csvFormatRow("1, Mario Rossi, 1:05.234, +0.0, 12, mario_r")
                                csvFormatRow("2, Luca Bianchi, 1:06.100, +0.8, 12,")
                            }

                            Text("La colonna \"username\" è opzionale: se presente associa il risultato all'account dell'utente.")
                                .font(.system(size: 11))
                                .foregroundColor(.kartDim)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 12)
                        }
                        .background(Color.kartPanel)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))

                        // ── Seleziona file ────────────────────────────────────
                        VStack(spacing: 12) {
                            Button {
                                showFilePicker = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .font(.system(size: 16))
                                    Text(selectedFileName ?? "Seleziona CSV dal Files")
                                        .font(.system(size: 14, weight: .bold))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .foregroundColor(selectedFileURL != nil ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(selectedFileURL != nil ? Color.kartAccent : Color.white.opacity(0.1))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedFileURL != nil ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                                )
                            }

                            // Pulsante upload
                            Button {
                                Task { await uploadCSV() }
                            } label: {
                                HStack(spacing: 10) {
                                    if isUploading {
                                        ProgressView().tint(.black).scaleEffect(0.85)
                                    } else {
                                        Image(systemName: "arrow.up.doc.fill")
                                            .font(.system(size: 16))
                                        Text("Carica Classifica")
                                            .font(.system(size: 15, weight: .bold))
                                    }
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(selectedFileURL != nil && !isUploading
                                            ? Color.green
                                            : Color.gray.opacity(0.4))
                                .cornerRadius(12)
                            }
                            .disabled(selectedFileURL == nil || isUploading)
                        }

                        // ── Risultato import ──────────────────────────────────
                        if let count = importedCount {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.system(size: 18))
                                    Text("\(count) risultat\(count == 1 ? "o" : "i") importat\(count == 1 ? "o" : "i") con successo")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 14)
                                .padding(.top, 12)

                                if !importErrors.isEmpty {
                                    Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 14)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(importErrors.count) avvertiment\(importErrors.count == 1 ? "o" : "i"):")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.yellow)
                                            .padding(.horizontal, 14)
                                        ForEach(importErrors, id: \.self) { err in
                                            Text("• \(err)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.yellow.opacity(0.85))
                                                .padding(.horizontal, 14)
                                        }
                                    }
                                    .padding(.bottom, 12)
                                } else {
                                    Spacer().frame(height: 8)
                                }
                            }
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.green.opacity(0.3), lineWidth: 1))
                        }

                        // ── Errore ────────────────────────────────────────────
                        if let err = errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(err)
                                    .font(.system(size: 13))
                                    .foregroundColor(.red)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Carica Risultati")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.kartAccent)
                        .font(.system(size: 14, weight: .semibold))
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText, UTType(filenameExtension: "csv") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            importErrors = []
            importedCount = nil
            errorMessage = nil
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                    selectedFileName = url.lastPathComponent
                }
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }

    // MARK: - Upload

    @MainActor
    private func uploadCSV() async {
        guard let fileURL = selectedFileURL,
              let httpURL = server.httpURL,
              let token = authState.currentToken else { return }

        isUploading = true
        errorMessage = nil
        importedCount = nil
        importErrors = []

        // Accesso sicuro al file (security scoped resource per Files app)
        let didStart = fileURL.startAccessingSecurityScopedResource()
        defer { if didStart { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let csvData = try Data(contentsOf: fileURL)
            let base = httpURL.absoluteString.replacingOccurrences(of: "/api", with: "")
            guard let uploadURL = URL(string: "\(base)/events/\(event.id)/results/import_csv") else { return }

            let boundary = "Boundary-\(UUID().uuidString)"
            var request = URLRequest(url: uploadURL)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            let filename = fileURL.lastPathComponent
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
            body.append(csvData)
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    struct ImportResp: Decodable { let imported: Int; let errors: [String] }
                    if let resp = try? JSONDecoder().decode(ImportResp.self, from: data) {
                        importedCount = resp.imported
                        importErrors = resp.errors
                    } else {
                        importedCount = 0
                    }
                } else {
                    let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
                        ?? "Errore \(http.statusCode)"
                    errorMessage = msg
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isUploading = false
    }

    // MARK: - Helpers

    private func csvFormatRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 2)
    }
}
