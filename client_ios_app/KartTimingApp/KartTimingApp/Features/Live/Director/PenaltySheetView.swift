import SwiftUI

/// Sheet per assegnare una penalità a un kart specifico.
struct PenaltySheetView: View {
    let kartAssignment: LiveKartAssignment
    @ObservedObject var viewModel: LiveViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: PenaltyPreset = .driveThroughs
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

                            ForEach(PenaltyPreset.allCases) { preset in
                                Button(action: {
                                    withAnimation(.spring(response: 0.25)) {
                                        selectedPreset = preset
                                        if !preset.requiresSeconds { seconds = "" }
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: preset.systemIcon)
                                            .font(.system(size: 18))
                                            .foregroundColor(selectedPreset == preset ? .kartAccent : .kartDim)
                                            .frame(width: 28)

                                        Text(preset.label)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(selectedPreset == preset ? .white : .kartDim)

                                        Spacer()

                                        if selectedPreset == preset {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.kartAccent)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedPreset == preset
                                                  ? Color.kartAccent.opacity(0.12)
                                                  : Color.kartPanel)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                selectedPreset == preset
                                                    ? Color.kartAccent.opacity(0.4)
                                                    : Color.white.opacity(0.05),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Secondi (solo per stop_go e time_added)
                        if selectedPreset.requiresSeconds {
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
    }

    private func confirm() {
        let sec: Int? = selectedPreset.requiresSeconds ? Int(seconds) : nil
        if selectedPreset.requiresSeconds && sec == nil {
            errorMsg = "Inserisci un numero di secondi valido."
            return
        }
        isLoading = true
        errorMsg = nil
        Task {
            do {
                try await viewModel.addPenalty(
                    kartNumber: kartAssignment.kartNumber,
                    type: selectedPreset,
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
