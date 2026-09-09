import SwiftUI

/// Vista Messaggi Live per gli utenti (sola lettura).
/// Mostra la cronologia messaggi e penalità senza permettere eliminazioni.
struct UserMessaggiView: View {
    @ObservedObject var viewModel: LiveViewModel

    enum LogItem: Identifiable {
        case message(RaceMessage)
        case penalty(RacePenalty)

        var id: String {
            switch self {
            case .message(let m): return "msg_\(m.id)"
            case .penalty(let p): return "pen_\(p.id)"
            }
        }

        var date: Date {
            switch self {
            case .message(let m): return m.parsedDate ?? Date.distantPast
            case .penalty(let p): return p.parsedDate ?? Date.distantPast
            }
        }
    }

    var combinedLog: [LogItem] {
        let msgs = viewModel.messages.map { LogItem.message($0) }
        let pens = viewModel.penalties.map { LogItem.penalty($0) }
        return (msgs + pens).sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CRONOLOGIA MESSAGGI")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartDim)
                            Text("Log comunicazioni e penalità")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        // Badge "sola lettura"
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 9))
                            Text("SOLA LETTURA")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.kartDim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.kartPanel)

                Divider().background(Color.white.opacity(0.06))

                if combinedLog.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 40))
                            .foregroundColor(.kartDim.opacity(0.4))
                        Text("Nessun messaggio o penalità")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.kartDim)
                    }
                    .padding(32)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(combinedLog) { item in
                                switch item {
                                case .message(let msg):
                                    UserMessageRow(message: msg)
                                case .penalty(let pen):
                                    UserPenaltyLogRow(penalty: pen)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
    }
}

// MARK: - User Message Row (read-only)

struct UserMessageRow: View {
    let message: RaceMessage

    private var accentColor: Color {
        switch message.messageType {
        case "yellow_flag": return .yellow
        case "red_flag":    return .red
        case "green_flag":  return .green
        case "checkered_flag": return Color(white: 0.9)
        default:            return .cyan
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let iconName: String = {
                if message.messageType == "checkered_flag" { return "flag.checkered.2.crossed" }
                return message.isBroadcast ? "antenna.radiowaves.left.and.right" : "flag.fill"
            }()

            Image(systemName: iconName)
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
                        Text(message.messageType == "checkered_flag" ? "FINE GARA" : "BROADCAST")
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
            // Nessun pulsante elimina
        }
        .padding(12)
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - User Penalty Log Row (read-only)

struct UserPenaltyLogRow: View {
    let penalty: RacePenalty

    var body: some View {
        HStack(spacing: 10) {
            Text("#\(penalty.kartNumber)")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundColor(.kartAccent)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: penalty.isWarning ? "exclamationmark.bubble.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(penalty.isWarning ? .kartDim : .yellow)
                        .font(.system(size: 11))
                    Text(penalty.displayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                if let note = penalty.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                }
            }

            Spacer()

            if let date = penalty.parsedDate {
                Text(date, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
            // Nessun pulsante elimina
        }
        .padding(12)
        .background(Color.kartPanel)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(penalty.isWarning ? Color.white.opacity(0.15) : Color.yellow.opacity(0.3), lineWidth: 1))
    }
}
