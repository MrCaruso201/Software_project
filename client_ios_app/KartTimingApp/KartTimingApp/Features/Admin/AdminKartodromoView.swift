import SwiftUI

struct AdminKartodromoView: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = KartodromoViewModel()

    @State private var searchText = ""
    @State private var expandedId: Int? = nil
    @State private var kartodromoToDelete: Kartodromo? = nil
    @State private var showDeleteAlert = false

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
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                .environment(\.colorScheme, .light)
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
                        .foregroundColor(.orange)
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
                            .foregroundColor(.white)
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
                                    .foregroundColor(.orange)
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
                Divider().background(Color.white.opacity(0.1))

                VStack(alignment: .leading, spacing: 10) {
                    // URL timing
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "link")
                            .foregroundColor(.orange)
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
                                .foregroundColor(.orange)
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
                    k.attivo ? Color.white.opacity(0.05) : Color.kartRed.opacity(0.25),
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
                .foregroundColor(.white)
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
