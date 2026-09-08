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
    
    @State private var resultType: String = "final"

    // Cancellazione classifica
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var deleteSuccess = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        csvInfoSection
                        uploadSection
                        if deleteSuccess { deleteFeedbackSection }
                        if let count = importedCount { importSuccessSection(count) }
                        if let err = errorMessage { errorSection(err) }
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
            .alert("Cancella Classifica", isPresented: $showDeleteConfirm) {
                Button("Cancella", role: .destructive) { Task { await deleteResults() } }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Stai per eliminare tutti i risultati ufficiali di \"\(event.title)\". Questa operazione non è reversibile.")
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
            deleteSuccess = false
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

    // MARK: - Sub-views

    @ViewBuilder
    private var csvInfoSection: some View {
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
                csvFormatRow("Posizione, Kart, Squadra, Miglior Giro, Gap, Giri")
                csvFormatRow("1, 14, Team Alpha, 1:05.234, Leader, 46")
                csvFormatRow("2, 22, Team Beta, 1:06.100, +1 giro, 45")
                csvFormatRow("3, 7, Team Gamma, 1:06.810, +1 giro, 45")
            } else {
                csvFormatRow("Posizione, Kart, Pilota, Miglior Giro, Gap, Giri")
                csvFormatRow("1, 14, Mario Rossi, 1:05.234, Leader, 12")
                csvFormatRow("2, 22, Luca Bianchi, 1:06.100, +0.8, 12")
            }

            let hint = "La colonna \"Kart\" serve per abbinare automaticamente il risultato al giusto utente/team in base all'assegnazione fatta durante il live timing."
            Text(hint)
                .font(.system(size: 11))
                .foregroundColor(.kartDim)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }
    

    @ViewBuilder
    private var uploadSection: some View {
        VStack(spacing: 12) {
            // Seleziona file
            Button { showFilePicker = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill").font(.system(size: 16))
                    Text(selectedFileName ?? "Seleziona CSV dal Files")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1).truncationMode(.middle)
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

            // Upload
            Button { Task { await uploadCSV() } } label: {
                HStack(spacing: 10) {
                    if isUploading {
                        ProgressView().tint(.black).scaleEffect(0.85)
                    } else {
                        Image(systemName: "arrow.up.doc.fill").font(.system(size: 16))
                        Text("Carica Classifica").font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selectedFileURL != nil && !isUploading ? Color.green : Color.gray.opacity(0.4))
                .cornerRadius(12)
            }
            .disabled(selectedFileURL == nil || isUploading)

            // Divisore
            HStack {
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                Text("oppure")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.kartDim)
                    .padding(.horizontal, 8)
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
            }

            // Cancella
            Button { showDeleteConfirm = true } label: {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView().tint(.red).scaleEffect(0.8)
                    } else {
                        Image(systemName: "trash.fill").font(.system(size: 14))
                        Text("Cancella Classifica").font(.system(size: 15, weight: .bold))
                    }
                }
                .foregroundColor(isDeleting ? .kartDim : .red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
            }
            .disabled(isDeleting || isUploading)
        }
    }

    @ViewBuilder
    private var deleteFeedbackSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.kartDim)
            Text("Classifica cancellata con successo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.kartDim)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    @ViewBuilder
    private func importSuccessSection(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green).font(.system(size: 18))
                Text("\(count) risultat\(count == 1 ? "o" : "i") importat\(count == 1 ? "o" : "i") con successo")
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.green)
            }
            .padding(.horizontal, 14).padding(.top, 12)

            if !importErrors.isEmpty {
                Divider().background(Color.white.opacity(0.08)).padding(.horizontal, 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(importErrors.count) avvertiment\(importErrors.count == 1 ? "o" : "i"):")
                        .font(.system(size: 11, weight: .bold)).foregroundColor(.yellow)
                        .padding(.horizontal, 14)
                    ForEach(importErrors, id: \.self) { err in
                        Text("• \(err)")
                            .font(.system(size: 11)).foregroundColor(.yellow.opacity(0.85))
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

    @ViewBuilder
    private func errorSection(_ err: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
            Text(err).font(.system(size: 13)).foregroundColor(.red)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.red.opacity(0.3), lineWidth: 1))
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
        deleteSuccess = false

        // Accesso sicuro al file (security scoped resource per Files app)
        let didStart = fileURL.startAccessingSecurityScopedResource()
        defer { if didStart { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let csvData = try Data(contentsOf: fileURL)
            let base = httpURL.absoluteString.replacingOccurrences(of: "/api", with: "")
            guard let uploadURL = URL(string: "\(base)/events/\(event.id)/results/import_csv?result_type=\(resultType)") else { return }

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

            let (data, response) = try await NetworkService.shared.data(for: request)

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

    // MARK: - Delete

    @MainActor
    private func deleteResults() async {
        guard let httpURL = server.httpURL,
              let token = authState.currentToken else { return }

        isDeleting = true
        errorMessage = nil
        importedCount = nil
        importErrors = []
        deleteSuccess = false

        let base = httpURL.absoluteString.replacingOccurrences(of: "/api", with: "")
        guard let deleteURL = URL(string: "\(base)/events/\(event.id)/results?result_type=\(resultType)") else {
            isDeleting = false
            return
        }

        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await NetworkService.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 204 {
                    deleteSuccess = true
                    selectedFileURL = nil
                    selectedFileName = nil
                } else {
                    let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["detail"]
                        ?? "Errore \(http.statusCode)"
                    errorMessage = msg
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isDeleting = false
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
