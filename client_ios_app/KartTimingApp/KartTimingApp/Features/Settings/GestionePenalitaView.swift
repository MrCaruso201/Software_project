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
            
            if viewModel.isLoadingPenaltyTypes {
                VStack {
                    ProgressView()
                        .tint(.kartAccent)
                    Text("Caricamento tipi penalità...")
                        .font(.body)
                        .foregroundColor(.kartDim)
                        .padding(.top, 8)
                }
            } else if let error = viewModel.penaltyTypesError {
                VStack(spacing: 16) {
                    Text(error)
                        .foregroundColor(.kartRed)
                        .multilineTextAlignment(.center)
                    Button("Riprova") {
                        Task { await viewModel.fetchPenaltyTypesOnly() }
                    }
                }
                .padding()
            } else if visiblePenalties.isEmpty {
                Text("Nessun tipo di penalità disponibile.")
                    .foregroundColor(.kartDim)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !actualPenalties.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("PENALITÀ")
                                    .font(.subheadline)
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
                                    .font(.subheadline)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var viewModel: LiveViewModel
    
    @State private var defaultSecondsStr: String = ""
    @State private var warningThresholdStr: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMsg: String? = nil
    @State private var isChanged: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let headerLayout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())
            headerLayout {
                Image(systemName: pType.systemIcon)
                    .font(.title3)
                    .foregroundColor(Color(uiColor: pType.isWarning ? .lightGray : .systemRed))
                
                Text(pType.name)
                    .font(.headline)
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
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.kartAction)
                                .foregroundColor(.white)
                                .cornerRadius(6)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(KartPressButtonStyle())
                    .accessibilityLabel("Salva " + pType.name)
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
                        .accessibilityLabel((pType.isWarning ? "Soglia avvisi, " : "Secondi, ") + pType.name)
                        .keyboardType(.numberPad)
                        .font(.body)
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
                        .accessibilityLabel((pType.isWarning ? "Soglia avvisi, " : "Secondi, ") + pType.name)
                        .keyboardType(.numberPad)
                        .font(.body)
                        .padding(8)
                        .background(Color.kartPanel)
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.kartBorder(opacity: 0.2), lineWidth: 1))
                    }
                }
            }
            .disabled(isSaving)
            
            if let err = errorMsg {
                Text(err)
                    .font(.caption)
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
        validateInput()
    }
    
    private func validateInput() {
        errorMsg = nil
        let secondsText = defaultSecondsStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let ds = Int(secondsText)
        if !secondsText.isEmpty && (ds == nil || ds! < 0) {
            errorMsg = "I secondi devono essere un numero intero maggiore o uguale a 0."
            return
        }
        let thresholdText = warningThresholdStr.trimmingCharacters(in: .whitespacesAndNewlines)
        let wt = Int(thresholdText)
        if !thresholdText.isEmpty && (wt == nil || wt! < 1) {
            errorMsg = "La soglia deve essere un numero intero maggiore o uguale a 1."
            return
        }
        
    }

    private func saveChanges() {
        validateInput()
        guard errorMsg == nil else { return }
        let ds = Int(defaultSecondsStr.trimmingCharacters(in: .whitespacesAndNewlines))
        let wt = Int(warningThresholdStr.trimmingCharacters(in: .whitespacesAndNewlines))
        isSaving = true
        errorMsg = nil
        Task {
            do {
                let updated = try await viewModel.updatePenaltyType(id: pType.id, defaultSeconds: ds, warningThreshold: wt)
                defaultSecondsStr = updated.defaultSeconds.map { String($0) } ?? ""
                warningThresholdStr = updated.warningThreshold.map { String($0) } ?? ""
                isChanged = false
            } catch {
                errorMsg = error.localizedDescription
            }
            isSaving = false
        }
    }
}
