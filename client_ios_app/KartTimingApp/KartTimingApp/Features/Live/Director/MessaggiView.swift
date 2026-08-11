import SwiftUI

/// Vista Messaggi Live per il Race Director.
/// Mostra la cronologia e permette di inviare nuovi messaggi (broadcast o per kart specifico).
struct MessaggiView: View {
    @ObservedObject var viewModel: LiveViewModel

    @State private var showComposeSheet = false
    @State private var actionError: String? = nil

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Cronologia messaggi")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.kartDim)
                    Spacer()
                    Button(action: { showComposeSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.bubble.fill")
                            Text("Invia")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(.kartAccent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.kartPanel)

                if viewModel.messages.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundColor(.kartDim.opacity(0.4))
                        Text("Nessun messaggio inviato")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.kartDim)
                    }
                    .padding(32)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.messages.reversed()) { msg in
                                MessageRow(message: msg, onDelete: {
                                    Task {
                                        do { try await viewModel.deleteMessage(id: msg.id) }
                                        catch { actionError = error.localizedDescription }
                                    }
                                })
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .sheet(isPresented: $showComposeSheet) {
            ComposeMessageSheet(viewModel: viewModel)
        }
        .alert("Errore", isPresented: .init(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: RaceMessage
    let onDelete: () -> Void

    private var accentColor: Color {
        switch message.messageType {
        case "yellow_flag": return .yellow
        case "red_flag":    return .red
        case "green_flag":  return .green
        default:            return .cyan
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Tipo icona
            Image(systemName: message.isBroadcast ? "antenna.radiowaves.left.and.right" : "flag.fill")
                .font(.system(size: 16))
                .foregroundColor(accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let kart = message.targetKart {
                        Text("Kart #\(kart)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartAccent)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.kartAccent.opacity(0.12))
                            .cornerRadius(4)
                    } else {
                        Text("BROADCAST")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(accentColor.opacity(0.12))
                            .cornerRadius(4)
                    }
                    Spacer()
                    if let date = message.parsedDate {
                        Text(date, style: .time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                }
                Text(message.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red.opacity(0.5))
                    .font(.system(size: 14))
            }
        }
        .padding(12)
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Compose Message Sheet

struct ComposeMessageSheet: View {
    @ObservedObject var viewModel: LiveViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPreset: MessagePreset = .yellowFlag
    @State private var customText: String = ""
    @State private var targetKartText: String = ""
    @State private var isBroadcast: Bool = true
    @State private var isLoading = false
    @State private var errorMsg: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.kartBG.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Destinatario
                        VStack(alignment: .leading, spacing: 10) {
                            Text("DESTINATARIO")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartAccent)

                            HStack(spacing: 12) {
                                Button(action: { isBroadcast = true }) {
                                    Label("Tutti", systemImage: "antenna.radiowaves.left.and.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(isBroadcast ? .black : .white)
                                        .padding(.vertical, 10).padding(.horizontal, 14)
                                        .background(isBroadcast ? Color.kartAccent : Color.kartPanel)
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                Button(action: { isBroadcast = false }) {
                                    Label("Kart specifico", systemImage: "flag.fill")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(!isBroadcast ? .black : .white)
                                        .padding(.vertical, 10).padding(.horizontal, 14)
                                        .background(!isBroadcast ? Color.kartAccent : Color.kartPanel)
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }

                            if !isBroadcast {
                                TextField("Numero kart", text: $targetKartText)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.kartPanel)
                                    .cornerRadius(12)
                            }
                        }

                        // Tipo messaggio
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TIPO MESSAGGIO")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartAccent)

                            ForEach(MessagePreset.allCases) { preset in
                                Button(action: {
                                    withAnimation(.spring(response: 0.25)) {
                                        selectedPreset = preset
                                        if preset != .custom && preset != .info {
                                            customText = preset.defaultText
                                        }
                                    }
                                }) {
                                    HStack {
                                        Text(preset.label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(selectedPreset == preset ? .white : .kartDim)
                                        Spacer()
                                        if selectedPreset == preset {
                                            Image(systemName: "checkmark.circle.fill").foregroundColor(.kartAccent)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedPreset == preset
                                                  ? Color.kartAccent.opacity(0.12) : Color.kartPanel)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedPreset == preset
                                                    ? Color.kartAccent.opacity(0.4) : Color.white.opacity(0.05),
                                                    lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Testo
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TESTO DEL MESSAGGIO")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartAccent)
                            TextField("Scrivi il messaggio...", text: $customText, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.kartPanel)
                                .cornerRadius(12)
                        }

                        if let err = errorMsg {
                            Text(err).font(.system(size: 12)).foregroundColor(.red)
                        }

                        // Invia
                        Button(action: send) {
                            HStack {
                                if isLoading { ProgressView().tint(.black).scaleEffect(0.8) }
                                else {
                                    Image(systemName: "paperplane.fill")
                                    Text("Invia Messaggio").font(.system(size: 15, weight: .bold))
                                }
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.kartAccent)
                            .cornerRadius(14)
                        }
                        .disabled(isLoading || customText.isEmpty)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Invia Messaggio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Annulla") { dismiss() }.foregroundColor(.kartDim)
                }
            }
            .onAppear {
                customText = selectedPreset.defaultText
            }
        }
    }

    private func send() {
        guard !customText.isEmpty else { return }
        let targetKart: Int? = isBroadcast ? nil : Int(targetKartText)
        if !isBroadcast && targetKart == nil {
            errorMsg = "Inserisci un numero kart valido."
            return
        }
        isLoading = true
        errorMsg = nil
        Task {
            do {
                try await viewModel.sendMessage(targetKart: targetKart, type: selectedPreset, text: customText)
                dismiss()
            } catch {
                errorMsg = error.localizedDescription
            }
            isLoading = false
        }
    }
}
