import SwiftUI

/// Team View — mostra posizione, penalità e messaggi dell'intera squadra.
struct TeamLiveView: View {
    var event: RaceEvent?
    @ObservedObject var viewModel: LiveViewModel

    var myKart: MyKartResponse { viewModel.myKart }

    @State private var showingBlueFlagCard = false
    @State private var processedBlueFlagIds: Set<Int> = []
    @State private var currentDriverIndex: Int = 0
    @State private var nextDriverIndex: Int = 1


    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if myKart.kartNumber == nil && myKart.teamId == nil {
                noKartState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let flag = activeFlag {
                            currentFlagCard(flag)
                        }
                        kartHeroCard
                        if event?.weightLimit != nil { weightCard }
                        if !myKart.penalties.isEmpty { penaltiesCard }
                        if myKart.penalties.isEmpty && activeFlag == nil { allClearCard }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
        .onAppear {
            checkForNewBlueFlags()
        }
        .onChange(of: myKart.penalties.count) { _, _ in
            checkForNewBlueFlags()
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

    enum TeamActiveFlag {
        case black
        case blue
        case broadcast(RaceMessage)
    }

    private var activeFlag: TeamActiveFlag? {
        if myKart.penalties.contains(where: { $0.penaltyType == "black_flag" }) {
            return .black
        }
        if showingBlueFlagCard {
            return .blue
        }
        if let msg = currentFlagMessage {
            return .broadcast(msg)
        }
        return nil
    }

    // MARK: - Weight Card

    private var weightCard: some View {
        Group {
            if let minLimit = event?.weightLimit {
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 6) {
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.purple)
                        Text("PESO E ZAVORRA")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        Spacer()
                        Text("Min. \(minLimit, specifier: "%.0f") kg")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                    .padding(14)
                    .background(Color.purple.opacity(0.08))

                    // Righe membri
                    let members: [(name: String, weight: Double?)] = {
                        if !myKart.teamMembers.isEmpty {
                            return myKart.teamMembers.map { ($0.username ?? "Membro", $0.weight) }
                        } else {
                            let name = AuthState.shared.currentUser?.username ?? "Tu"
                            return [(name, myKart.weight)]
                        }
                    }()

                    VStack(spacing: 0) {
                        ForEach(Array(members.enumerated()), id: \.offset) { _, member in
                            weightMemberRow(name: member.name, weight: member.weight, minLimit: minLimit)
                            if member.name != members.last?.name {
                                Divider().background(Color.white.opacity(0.05)).padding(.leading, 14)
                            }
                        }
                    }

                    // Sezione cambio pilota (solo se ci sono ≥2 membri con peso)
                    if members.count >= 2 {
                        driverSwapSection(members: members, minLimit: minLimit)
                    }
                }
                .background(Color.kartPanel)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.purple.opacity(0.2), lineWidth: 1))
            }
        }
    }

    private func driverSwapSection(members: [(name: String, weight: Double?)], minLimit: Double) -> some View {
        let safeCurrentIdx = min(currentDriverIndex, members.count - 1)
        let safeNextIdx = min(nextDriverIndex, members.count - 1)
        let currentDriver = members[safeCurrentIdx]
        let nextDriver = members[safeNextIdx]

        // Calcola la zavorra attuale del pilota corrente e quella del prossimo
        let currentBallast: Int = {
            guard let w = currentDriver.weight else { return 0 }
            let diff = minLimit - w
            return diff > 0 ? Int(ceil(diff / 5.0)) * 5 : 0
        }()
        let nextBallast: Int = {
            guard let w = nextDriver.weight else { return 0 }
            let diff = minLimit - w
            return diff > 0 ? Int(ceil(diff / 5.0)) * 5 : 0
        }()
        let delta = nextBallast - currentBallast  // positivo = aggiungere, negativo = togliere

        let bothKnown = currentDriver.weight != nil && nextDriver.weight != nil
        let sameDriver = safeCurrentIdx == safeNextIdx

        return VStack(spacing: 0) {
            Divider().background(Color.white.opacity(0.08))

            VStack(spacing: 12) {
                // Header sezione
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.cyan)
                    Text("CAMBIO PILOTA")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                }

                // Picker affiancati
                HStack(spacing: 10) {
                    // Pilota attuale
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATTUALE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                        Picker("", selection: $currentDriverIndex) {
                            ForEach(members.indices, id: \.self) { i in
                                Text(members[i].name).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.kartDim)

                    // Pilota successivo
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUCCESSIVO")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                        Picker("", selection: $nextDriverIndex) {
                            ForEach(members.indices, id: \.self) { i in
                                Text(members[i].name).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity)
                }

                // Risultato cambio
                if sameDriver {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.kartDim)
                        Text("Seleziona due piloti diversi")
                            .font(.system(size: 12))
                            .foregroundColor(.kartDim)
                    }
                    .padding(.vertical, 6)
                } else if !bothKnown {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Peso mancante: impossibile calcolare")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.yellow)
                    }
                    .padding(.vertical, 6)
                } else if delta == 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "equal.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nessun cambio zavorra")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("I due piloti richiedono la stessa zavorra")
                                .font(.system(size: 11))
                                .foregroundColor(.kartDim)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } else {
                    let isAdding = delta > 0
                    HStack(spacing: 10) {
                        Image(systemName: isAdding ? "plus.circle.fill" : "minus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(isAdding ? .orange : .cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isAdding ? "Aggiungi \(abs(delta)) kg" : "Togli \(abs(delta)) kg")
                                .font(.system(size: 16, weight: .black, design: .monospaced))
                                .foregroundColor(isAdding ? .orange : .cyan)
                            Text(isAdding ? "Aggiungere zavorra al kart" : "Rimuovere zavorra dal kart")
                                .font(.system(size: 11))
                                .foregroundColor(.kartDim)
                        }
                        Spacer()
                        // Zavorra finale del prossimo pilota
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(nextBallast) kg")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                            Text("zavorra totale")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(14)
            .background(Color.cyan.opacity(0.05))
        }
    }

    private func weightMemberRow(name: String, weight: Double?, minLimit: Double) -> some View {
        let requiredWeight: Int = {
            guard let w = weight else { return -1 }
            let diff = minLimit - w
            return diff > 0 ? Int(ceil(diff / 5.0)) * 5 : 0
        }()

        let accentColor: Color = {
            if weight == nil { return .yellow }
            return requiredWeight > 0 ? .orange : .green
        }()

        return HStack(spacing: 12) {
            Image(systemName: weight == nil ? "exclamationmark.triangle.fill" : (requiredWeight > 0 ? "scalemass.fill" : "checkmark.seal.fill"))
                .font(.system(size: 18))
                .foregroundColor(accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                if let w = weight {
                    Text("\(w, specifier: "%.1f") kg personali")
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                } else {
                    Text("Peso non impostato")
                        .font(.system(size: 11))
                        .foregroundColor(.kartDim)
                }
            }

            Spacer()

            if weight == nil {
                Text("?")
                    .font(.system(size: 15, weight: .black, design: .monospaced))
                    .foregroundColor(.yellow)
            } else if requiredWeight > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("+\(requiredWeight) kg")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(.orange)
                    Text("zavorra")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.7))
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

                // NUMERO KART, STINT E PENALITÀ
                HStack(spacing: 10) {
                    VStack(spacing: 6) {
                        if let kart = myKart.kartNumber {
                            Text("#\(kart)")
                                .font(.system(size: 36, weight: .black, design: .monospaced))
                                .foregroundColor(.kartAccent)
                        } else {
                            Text("—")
                                .font(.system(size: 36, weight: .black, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                        Text("KART")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                    .frame(maxWidth: .infinity)

                    Divider().background(Color.white.opacity(0.1)).frame(height: 50)

                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                        VStack(spacing: 6) {
                            Text(formatStint(myKart.currentStintDuration))
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(myKart.isInPit ? .red : .white)
                            Text("STINT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Divider().background(Color.white.opacity(0.1)).frame(height: 50)

                    VStack(spacing: 6) {
                        Text("+\(myKart.totalPenaltySeconds)s")
                            .font(.system(size: 36, weight: .black, design: .monospaced))
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

    private func formatStint(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "00:00"
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

    private func currentFlagCard(_ status: TeamActiveFlag) -> some View {
        let (bg, fg, icon, label): (Color, Color, String, String) = {
            switch status {
            case .black:
                return (.red, .black, "flag.fill", "BANDIERA NERA")
            case .blue:
                return (.blue, .white, "flag.fill", "BANDIERA BLU")
            case .broadcast(let msg):
                switch msg.messageType {
                case "yellow_flag":    return (.yellow,        .black, "flag.fill",                "BANDIERA GIALLA")
                case "red_flag":        return (.red,           .white, "flag.fill",                "BANDIERA ROSSA")
                case "green_flag":      return (Color.kartGreen,.black, "flag.fill",                "BANDIERA VERDE")
                case "checkered_flag": return (Color.white,    .black, "flag.checkered.2.crossed", "BANDIERA A SCACCHI")
                case "custom":          return (Color.kartGreen,.black, "flag.fill",                "GARA IN CORSO")
                default:                return (.gray,          .white, "flag.fill",                "BANDIERA")
                }
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

    // MARK: - Blue Flag Logic

    private func checkForNewBlueFlags() {
        for penalty in myKart.penalties where penalty.penaltyType == "blue_flag" {
            if !processedBlueFlagIds.contains(penalty.id) {
                processedBlueFlagIds.insert(penalty.id)
                
                let age = penalty.parsedDate.map { Date().timeIntervalSince($0) } ?? 0
                if age < 5 {
                    showingBlueFlagCard = true
                    let remainingTime = 5 - age
                    DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) {
                        showingBlueFlagCard = false
                    }
                }
            }
        }
    }
}
