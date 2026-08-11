import SwiftUI

/// Sheet per assegnare una penalità a un kart specifico.
struct PenaltySheetView: View {
    let kartAssignment: LiveKartAssignment
    @ObservedObject var viewModel: LiveViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: PenaltyType? = nil
    @State private var seconds: String = ""
    @State private var note: String = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Kart header
                        HStack {
                            Text("#\(kartAssignment.kartNumber)")
                                .font(.system(size: 40, weight: .black, design: .monospaced))
                                .foregroundColor(.kartAccent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(kartAssignment.teamName ?? "Team")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text("Seleziona tipo di penalità")
                                    .font(.system(size: 12))
                                    .foregroundColor(.kartDim)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(Color.kartPanel)
                        .cornerRadius(14)

                        // Tipo penalità
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TIPO PENALITÀ")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartAccent)

                            ForEach(viewModel.penaltyTypes) { pType in
                                Button(action: {
                                    withAnimation(.spring(response: 0.25)) {
                                        selectedType = pType
                                        if let defSec = pType.defaultSeconds {
                                            seconds = String(defSec)
                                        } else if !pType.requiresSeconds {
                                            seconds = ""
                                        }
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: pType.systemIcon)
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedType?.id == pType.id ? .kartAccent : .kartDim)
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(pType.name.uppercased())
                                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                .foregroundColor(selectedType?.id == pType.id ? .white : .kartDim)
                                            
                                            // Show auto-penalty hint if threshold exists
                                            if let threshold = pType.warningThreshold {
                                                Text("Auto-penalty alla \(threshold)ª volta")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.kartAccent.opacity(0.8))
                                            }
                                        }
                                        Spacer()
                                        if selectedType?.id == pType.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.kartAccent)
                                                .font(.system(size: 14, weight: .bold))
                                        }
                                    }
                                    .padding()
                                    .background(selectedType?.id == pType.id ? Color.kartAccent.opacity(0.15) : Color.kartPanel)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedType?.id == pType.id ? Color.kartAccent : Color.white.opacity(0.05), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Secondi (solo per stop_go e time_added)
                        if let selected = selectedType, selected.requiresSeconds {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("SECONDI DI PENALITÀ")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.kartAccent)
                                TextField("Es. 10", text: $seconds)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 24, weight: .black, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.kartPanel)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.kartAccent.opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }

                        // Nota libera
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NOTA (OPZIONALE)")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartDim)
                            TextField("Descrizione...", text: $note)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.kartPanel)
                                .cornerRadius(12)
                        }

                        if let err = errorMsg {
                            Text(err)
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }

                        // Bottone conferma
                        Button(action: confirm) {
                            HStack {
                                if isLoading {
                                    ProgressView().tint(.black).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("Assegna Penalità")
                                        .font(.system(size: 15, weight: .bold))
                                }
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.kartAccent)
                            .cornerRadius(14)
                        }
                        .disabled(isLoading)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Penalità Kart #\(kartAssignment.kartNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }.foregroundColor(.kartDim)
                }
            }
        }
        .onAppear {
            if selectedType == nil, let first = viewModel.penaltyTypes.first {
                selectedType = first
                if let defSec = first.defaultSeconds {
                    seconds = String(defSec)
                }
            }
        }
    }

    private func confirm() {
        guard let selected = selectedType else {
            errorMsg = "Seleziona un tipo di penalità."
            return
        }
        
        let sec: Int? = selected.requiresSeconds ? Int(seconds) : nil
        if selected.requiresSeconds && sec == nil {
            errorMsg = "Inserisci un numero di secondi valido."
            return
        }
        isLoading = true
        errorMsg = nil
        Task {
            do {
                try await viewModel.addPenalty(
                    kartNumber: kartAssignment.kartNumber,
                    type: selected,
                    seconds: sec,
                    note: note.isEmpty ? nil : note
                )
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}
