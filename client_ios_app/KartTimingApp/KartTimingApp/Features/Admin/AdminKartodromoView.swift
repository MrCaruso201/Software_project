import SwiftUI
import PhotosUI

struct AdminKartodromoView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = KartodromoViewModel()

    @State private var searchText = ""
    @State private var expandedId: Int? = nil
    @State private var kartodromoToDelete: Kartodromo? = nil
    @State private var showDeleteAlert = false
    @State private var uploadingId: Int? = nil
    @State private var uploadResult: (id: Int, success: Bool)? = nil

    enum ActiveSheet: Identifiable {
        case new
        case edit(Kartodromo)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let k): return "edit-\(k.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet? = nil

    var filtered: [Kartodromo] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return viewModel.kartodromi }
        return viewModel.kartodromi.filter {
            $0.nome.lowercased().contains(q) ||
            $0.luogo.lowercased().contains(q) ||
            $0.url.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                if viewModel.isLoading {
                    Spacer()
                    ProgressView().tint(.kartAccent).scaleEffect(1.3)
                    Text("Caricamento circuiti...")
                        .foregroundColor(.kartDim)
                        .font(.caption)
                        .padding(.top, 8)
                    Spacer()
                } else if let err = viewModel.errorMessage {
                    Spacer()
                    Text(err)
                        .foregroundColor(.kartRed)
                        .multilineTextAlignment(.center)
                        .padding()
                    Spacer()
                } else if filtered.isEmpty {
                    Spacer()
                    Image(systemName: "mappin.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.kartDim)
                    Text("Nessun circuito trovato")
                        .foregroundColor(.kartDim)
                        .padding(.top, 8)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filtered) { k in
                                kartodromoRow(k)
                            }
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 30)
                    }
                }
            }
        }
        .navigationTitle("Circuiti")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Barra ricerca stile Live Timing
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                    TextField("", text: $searchText, prompt: Text("CERCA CIRCUITO").foregroundColor(.black))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.black)
                        .multilineTextAlignment(.center)
                        .disableAutocorrection(true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.82, blue: 0.0),
                                 Color(red: 1.0, green: 0.65, blue: 0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.4), radius: 6, x: 0, y: 3)
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeSheet = .new
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.kartWarning)
                }
            }
        }
        .sheet(item: $activeSheet) { sheetType in
            switch sheetType {
            case .new:
                KartodromoFormView(
                    server: server,
                    authState: authState,
                    viewModel: viewModel,
                    editingKartodromo: nil
                )
            case .edit(let k):
                KartodromoFormView(
                    server: server,
                    authState: authState,
                    viewModel: viewModel,
                    editingKartodromo: k
                )
            }
        }
        .alert("Elimina circuito", isPresented: $showDeleteAlert, presenting: kartodromoToDelete) { k in
            Button("Elimina", role: .destructive) { deleteKartodromo(k) }
            Button("Annulla", role: .cancel) {}
        } message: { k in
            Text("Sei sicuro di voler eliminare «\(k.nome)»? L'operazione è irreversibile.")
        }
        .onAppear {
            if viewModel.kartodromi.isEmpty {
                viewModel.fetchAll(serverURL: server.httpURL, token: authState.currentToken)
            }
        }
    }

    // MARK: - Row

    private func kartodromoRow(_ k: Kartodromo) -> some View {
        let isExpanded = expandedId == k.id

        return VStack(spacing: 0) {
            // Header sempre visibile
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(k.nome)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.kartForeground)
                        if !k.attivo {
                            Text("INATTIVO")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.kartRed)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.kartRed.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 12) {
                        if !k.luogo.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.kartWarning)
                                Text(k.luogo)
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.kartDim)
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.kartDim)
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.kartPanel)

            // Corpo espanso
            if isExpanded {
                Divider().background(Color.kartBorder(opacity: 0.1))

                VStack(alignment: .leading, spacing: 10) {
                    // URL timing
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "link")
                            .foregroundColor(.kartWarning)
                            .font(.system(size: 12))
                        Text(k.url)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.kartDim)
                            .lineLimit(2)
                    }

                    // Sito web (se presente)
                    if !k.sitoWeb.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "globe")
                                .foregroundColor(.kartWarning)
                                .font(.system(size: 12))
                            Text(k.sitoWeb)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.kartDim)
                                .lineLimit(2)
                        }
                    }

                    // Pulsanti azione
                    HStack(spacing: 12) {
                        Button {
                            activeSheet = .edit(k)
                        } label: {
                            Text("Modifica")
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.orange)
                                .foregroundColor(.black)
                                .cornerRadius(8)
                        }

                        Button {
                            kartodromoToDelete = k
                            showDeleteAlert = true
                        } label: {
                            Text("Elimina")
                                .font(.system(size: 12, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.kartRed.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }

                    // Upload grafica circuito
                    PhotosPicker(
                        selection: Binding(
                            get: { nil },
                            set: { item in
                                guard let item = item else { return }
                                uploadingId = k.id
                                item.loadTransferable(type: Data.self) { result in
                                    DispatchQueue.main.async {
                                        switch result {
                                        case .success(let data):
                                            if let data = data {
                                                viewModel.uploadImage(
                                                    serverURL: server.httpURL,
                                                    kartodromoId: k.id,
                                                    imageData: data,
                                                    fileName: "circuit_\(k.id).png",
                                                    mimeType: "image/png",
                                                    token: authState.currentToken
                                                ) { success in
                                                    uploadingId = nil
                                                    uploadResult = (id: k.id, success: success)
                                                    // Reset dopo 2 secondi
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                        uploadResult = nil
                                                    }
                                                }
                                            }
                                        case .failure:
                                            uploadingId = nil
                                        }
                                    }
                                }
                            }
                        ),
                        matching: .images
                    ) {
                        HStack(spacing: 6) {
                            if uploadingId == k.id {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.8)
                            } else if let res = uploadResult, res.id == k.id {
                                Image(systemName: res.success ? "checkmark" : "xmark")
                                    .font(.system(size: 11, weight: .bold))
                            } else {
                                Image(systemName: k.imageUrl != nil ? "photo.badge.checkmark" : "photo.badge.plus")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(k.imageUrl != nil ? "Sostituisci grafica" : "Carica grafica circuito")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            uploadResult?.id == k.id
                                ? (uploadResult!.success ? Color.green.opacity(0.8) : Color.kartRed.opacity(0.7))
                                : Color.kartBG
                        )
                        .foregroundColor(.kartForeground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.kartBorder(opacity: 0.15), lineWidth: 1)
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.kartPanel.opacity(0.95))
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    k.attivo ? Color.kartForeground.opacity(0.05) : Color.kartRed.opacity(0.25),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                expandedId = isExpanded ? nil : k.id
            }
        }
    }

    // MARK: - Header bar

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("Circuiti nel sistema")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.kartForeground)
            Spacer()
            Text("\(filtered.count) trovati")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.kartDim)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.kartPanel)
    }

    // MARK: - Actions

    private func deleteKartodromo(_ k: Kartodromo) {
        viewModel.delete(
            serverURL: server.httpURL,
            kartodromoId: k.id,
            token: authState.currentToken
        ) { _ in }
    }
}
