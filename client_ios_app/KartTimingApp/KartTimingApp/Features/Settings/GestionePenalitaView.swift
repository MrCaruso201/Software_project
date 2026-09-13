import SwiftUI

struct GestionePenalitaView: View {
    let server: DiscoveredServer
    @StateObject private var viewModel = LiveViewModel()
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var appEnv: AppEnvironment
    
    private var visiblePenalties: [PenaltyType] {
        viewModel.penaltyTypes.filter {
            !["black_flag", "blue_flag", "drop_position", "custom"].contains($0.code)
        }
    }
    
    private var actualPenalties: [PenaltyType] {
        visiblePenalties.filter { !$0.isWarning }
    }
    
    private var warningPenalties: [PenaltyType] {
        visiblePenalties.filter { $0.isWarning }
    }
    
    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            if viewModel.penaltyTypes.isEmpty {
                VStack {
                    ProgressView()
                        .tint(.kartAccent)
                    Text("Caricamento tipi penalità...")
                        .font(.system(size: 14))
                        .foregroundColor(.kartDim)
                        .padding(.top, 8)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !actualPenalties.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PENALITÀ")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.kartDim)
                                
                                VStack(spacing: 16) {
                                    ForEach(actualPenalties) { pType in
                                        PenaltyTypeEditorRow(pType: pType, viewModel: viewModel)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        
                        if !warningPenalties.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("WARNING (AVVISI)")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.kartDim)
                                
                                VStack(spacing: 16) {
                                    ForEach(warningPenalties) { pType in
                                        PenaltyTypeEditorRow(pType: pType, viewModel: viewModel)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Gestione Penalità")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.configure(serverURL: server.httpURL, token: authState.currentToken, eventId: 0)
            Task {
                await viewModel.fetchPenaltyTypesOnly()
            }
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

struct PenaltyTypeEditorRow: View {
    let pType: PenaltyType
    @ObservedObject var viewModel: LiveViewModel
    
    @State private var defaultSecondsStr: String = ""
    @State private var warningThresholdStr: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMsg: String? = nil
    @State private var isChanged: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: pType.systemIcon)
                    .font(.system(size: 20))
                    .foregroundColor(Color(uiColor: pType.isWarning ? .lightGray : .systemRed))
                
                Text(pType.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.kartForeground)
                
                Spacer()
                
                if isChanged {
                    Button {
                        saveChanges()
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Salva")
                                .font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.kartAccent)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    .disabled(isSaving)
                }
            }
            
            Divider().background(Color.kartBorder(opacity: 0.1))
            
            // Editable fields
            HStack(spacing: 16) {
                if !pType.isWarning {
                    // Default seconds
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tempo (secondi)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.kartDim)
                        
                        TextField("Es: 10", text: Binding(
                            get: { defaultSecondsStr },
                            set: {
                                defaultSecondsStr = $0
                                checkChanged()
                            }
                        ))
                        .keyboardType(.numberPad)
                        .font(.system(size: 14))
                        .padding(8)
                        .background(Color.kartPanel)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.kartBorder(opacity: 0.2), lineWidth: 1))
                    }
                }
                
                if pType.isWarning {
                    // Warning threshold
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Soglia Auto-Penalità")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.kartDim)
                        
                        TextField("Nessuna", text: Binding(
                            get: { warningThresholdStr },
                            set: {
                                warningThresholdStr = $0
                                checkChanged()
                            }
                        ))
                        .keyboardType(.numberPad)
                        .font(.system(size: 14))
                        .padding(8)
                        .background(Color.kartPanel)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.kartBorder(opacity: 0.2), lineWidth: 1))
                    }
                }
            }
            
            if let err = errorMsg {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundColor(.kartRed)
            }
        }
        .padding(16)
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1))
        .onAppear {
            if let ds = pType.defaultSeconds {
                defaultSecondsStr = String(ds)
            }
            if let wt = pType.warningThreshold {
                warningThresholdStr = String(wt)
            }
        }
        .onChange(of: pType.defaultSeconds) { updateStateFromModel() }
        .onChange(of: pType.warningThreshold) { updateStateFromModel() }
    }
    
    private func updateStateFromModel() {
        if let ds = pType.defaultSeconds { defaultSecondsStr = String(ds) } else { defaultSecondsStr = "" }
        if let wt = pType.warningThreshold { warningThresholdStr = String(wt) } else { warningThresholdStr = "" }
        isChanged = false
    }
    
    private func checkChanged() {
        let currentDs = pType.defaultSeconds.map { String($0) } ?? ""
        let currentWt = pType.warningThreshold.map { String($0) } ?? ""
        isChanged = (defaultSecondsStr != currentDs) || (warningThresholdStr != currentWt)
    }
    
    private func saveChanges() {
        let ds = Int(defaultSecondsStr)
        let wt = Int(warningThresholdStr)
        
        isSaving = true
        errorMsg = nil
        Task {
            do {
                try await viewModel.updatePenaltyType(id: pType.id, defaultSeconds: ds, warningThreshold: wt)
                isChanged = false
            } catch {
                errorMsg = error.localizedDescription
            }
            isSaving = false
        }
    }
}
