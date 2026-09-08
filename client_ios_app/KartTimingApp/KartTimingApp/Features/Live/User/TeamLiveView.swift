import SwiftUI

/// Team View — mostra posizione, penalità e messaggi dell'intera squadra.
struct TeamLiveView: View {
    @ObservedObject var viewModel: LiveViewModel

    var myKart: MyKartResponse { viewModel.myKart }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if myKart.kartNumber == nil && myKart.teamId == nil {
                noKartState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let flag = currentFlagMessage {
                            currentFlagCard(flag)
                        }
                        kartHeroCard
                        if !myKart.penalties.isEmpty { penaltiesCard }
                        if !myKart.messages.isEmpty { messagesCard }
                        if myKart.penalties.isEmpty && myKart.messages.isEmpty && currentFlagMessage == nil { allClearCard }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    /// Ultima bandiera broadcast globale (per il banner).
    /// Include anche i messaggi custom "Gara Iniziata" (trattati come bandiera verde).
    private var currentFlagMessage: RaceMessage? {
        viewModel.messages
            .filter {
                $0.isBroadcast && (
                    ["yellow_flag", "red_flag", "green_flag", "checkered_flag"].contains($0.messageType)
                    || ($0.messageType == "custom" && $0.text.lowercased() == "gara iniziata")
                )
            }
            .sorted {
                guard let d1 = $0.parsedDate, let d2 = $1.parsedDate else { return false }
                return d1 < d2
            }
            .last
    }

    // MARK: - Kart Hero Card

    private var kartHeroCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "flag.2.crossed.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.kartAccent)
                Text("INFO SQUADRA")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartAccent)
                Spacer()
            }
            .padding(14)
            .background(Color.kartAccent.opacity(0.08))

            VStack(spacing: 24) {
                // NOME TEAM E MEMBRI
                VStack(spacing: 8) {
                    Text(myKart.teamName ?? "—")
                        .font(.system(size: 32, weight: .black))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        
                    if let teamId = myKart.teamId, let team = viewModel.registeredTeams.first(where: { $0.teamId == teamId }) {
                        let memberNames = team.members.compactMap { $0.username }.joined(separator: " • ")
                        Text(memberNames)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.kartDim)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Divider().background(Color.white.opacity(0.1))

                // NUMERO KART E PENALITÀ
                HStack(spacing: 20) {
                    VStack(spacing: 6) {
                        if let kart = myKart.kartNumber {
                            Text("#\(kart)")
                                .font(.system(size: 56, weight: .black, design: .monospaced))
                                .foregroundColor(.kartAccent)
                        } else {
                            Text("—")
                                .font(.system(size: 56, weight: .black, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                        Text("NUMERO KART")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().background(Color.white.opacity(0.1)).frame(height: 70)

                    VStack(spacing: 6) {
                        Text("+\(myKart.totalPenaltySeconds)s")
                            .font(.system(size: 56, weight: .black, design: .monospaced))
                            .foregroundColor(myKart.totalPenaltySeconds > 0 ? .orange : .kartDim)
                        Text("PENALITÀ")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Penalties Card

    private var penaltiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.yellow)
                Text("PENALITÀ E AVVISI")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
                Spacer()
                Text("+\(myKart.totalPenaltySeconds)s totali")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.yellow)
            }
            .padding(14)
            .background(Color.yellow.opacity(0.08))

            VStack(spacing: 0) {
                ForEach(myKart.penalties) { penalty in
                    HStack(spacing: 12) {
                        Image(systemName: penalty.isWarning ? "exclamationmark.bubble.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(penalty.isWarning ? .kartDim : .yellow)
                            .font(.system(size: 14))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(penalty.displayLabel)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            if let note = penalty.note, !note.isEmpty {
                                Text(note).font(.system(size: 11)).foregroundColor(.kartDim)
                            }
                        }

                        Spacer()

                        if let date = penalty.parsedDate {
                            Text(date, style: .time)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Divider().background(Color.white.opacity(0.05)).padding(.leading, 40)
                    }
                }
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Messages Card

    private var messagesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
                Text("MESSAGGI DAL DIRETTORE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.cyan)
                Spacer()
            }
            .padding(14)
            .background(Color.cyan.opacity(0.08))

            VStack(spacing: 0) {
                ForEach(myKart.messages.reversed()) { msg in
                    userMessageRow(msg)
                }
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
    }

    private func userMessageRow(_ msg: RaceMessage) -> some View {
        let isCheckered = msg.messageType == "checkered_flag"
        let color: Color = {
            switch msg.messageType {
            case "yellow_flag": return .yellow
            case "red_flag":    return .red
            case "green_flag":  return .green
            case "checkered_flag": return .white
            default:            return .cyan
            }
        }()

        return HStack(alignment: .top, spacing: 12) {
            if isCheckered {
                Image(systemName: "flag.checkered.2.crossed")
                    .font(.system(size: 10))
                    .foregroundColor(.black)
                    .frame(width: 18, height: 18)
                    .background(Color.white)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(msg.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    if msg.isBroadcast {
                        Text("Broadcast")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                    if let date = msg.parsedDate {
                        Text(date, style: .time)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.05)).padding(.leading, 30)
        }
    }

    // MARK: - All Clear

    private var allClearCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)
            Text("Tutto OK!")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
            Text("Nessuna penalità o messaggio ricevuto.")
                .font(.system(size: 12))
                .foregroundColor(.kartDim)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
        .background(Color.kartPanel)
        .cornerRadius(14)
    }

    // MARK: - Current Flag Card

    private func currentFlagCard(_ msg: RaceMessage) -> some View {
        let (bg, fg, icon, label): (Color, Color, String, String) = {
            switch msg.messageType {
            case "yellow_flag":    return (.yellow,        .black, "flag.fill",                "BANDIERA GIALLA")
            case "red_flag":        return (.red,           .white, "flag.fill",                "BANDIERA ROSSA")
            case "green_flag":      return (Color.kartGreen,.black, "flag.fill",                "BANDIERA VERDE")
            case "checkered_flag": return (Color.white,    .black, "flag.checkered.2.crossed", "BANDIERA A SCACCHI")
            case "custom":          return (Color.kartGreen,.black, "flag.fill",                "GARA IN CORSO")
            default:                return (.gray,          .white, "flag.fill",                "BANDIERA")
            }
        }()
        return VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(fg)
            Text(label)
                .font(.system(size: 22, weight: .black, design: .monospaced))
                .foregroundColor(fg)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(bg)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(fg.opacity(0.2), lineWidth: 1))
    }

    // MARK: - No Kart State

    private var noKartState: some View {
        VStack(spacing: 16) {
            Image(systemName: "number.circle")
                .font(.system(size: 52))
                .foregroundColor(.kartDim.opacity(0.4))
            Text("Nessun kart assegnato")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.kartDim)
            Text("Il Race Director non ha ancora assegnato un kart alla tua squadra.")
                .font(.system(size: 12))
                .foregroundColor(.kartDim.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
