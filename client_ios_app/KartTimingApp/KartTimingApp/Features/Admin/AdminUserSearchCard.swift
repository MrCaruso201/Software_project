import SwiftUI

struct AdminUserSearchCard: View {
    let server: DiscoveredServer
    @EnvironmentObject var authState: AuthState
    @StateObject private var viewModel = AdminUserSearchViewModel()
    @State private var isExpanded: Bool = false
    
    private var topResults: [UserProfile] {
        Array(viewModel.searchResults.prefix(10))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header ─────────────────────────────────────────────────────
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.kartAccent)
                    Text("UTENTI")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartAccent)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.kartAccent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.kartAccent.opacity(0.08))
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.kartDim)
                TextField("Cerca utente (nome, email...)", text: $viewModel.searchQuery)
                    .foregroundColor(.kartForeground)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            .padding(12)
            .background(Color.kartBG)
            .cornerRadius(10)
            .padding(16)
            
            // Results
            if viewModel.isLoading {
                HStack {
                    Spacer()
                    ProgressView().tint(.kartAccent)
                    Spacer()
                }
                .padding(.bottom, 16)
            } else if !viewModel.searchQuery.isEmpty && viewModel.searchResults.isEmpty {
                Text("Nessun utente trovato.")
                    .font(.system(size: 14))
                    .foregroundColor(.kartDim)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                // Mostra i primi 10 risultati
                VStack(spacing: 0) {
                    ForEach(Array(topResults.enumerated()), id: \.element.id) { idx, user in
                        NavigationLink {
                            AdminUserDetailView(user: user, server: server)
                                .environmentObject(authState)
                        } label: {
                            userRow(user: user)
                        }
                        .buttonStyle(.plain)
                        
                        if idx < topResults.count - 1 {
                            Divider()
                                .background(Color.kartForeground.opacity(0.06))
                                .padding(.leading, 60)
                        }
                } // ForEach
            } // VStack
            } // else
            } // if isExpanded
        } // outer VStack
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.06), lineWidth: 1))
        .onAppear {
            viewModel.setup(serverURL: server.httpURL, token: authState.currentToken)
        }
    }
    
    private func userRow(user: UserProfile) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .foregroundColor(.kartAccent)
            
            VStack(alignment: .leading, spacing: 2) {
                let fullName = "\(user.firstName ?? "") \(user.lastName ?? "")".trimmingCharacters(in: .whitespaces)
                Text(fullName.isEmpty ? user.username : fullName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.kartForeground)
                Text(user.email)
                    .font(.system(size: 12))
                    .foregroundColor(.kartDim)
            }
            Spacer()
            Text(user.role.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(roleColor(user.role))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(roleColor(user.role).opacity(0.2))
                .cornerRadius(4)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.kartDim)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private func roleColor(_ role: String) -> Color {
        switch role {
        case "admin": return .red
        case "race_director": return .orange
        default: return .green
        }
    }
}
