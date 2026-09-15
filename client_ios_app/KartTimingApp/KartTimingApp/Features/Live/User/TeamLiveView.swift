import SwiftUI

/// Team View — mostra posizione, penalità e messaggi dell'intera squadra.
struct TeamLiveView: View {
    @Environment(\.colorScheme) private var colorScheme
    var event: RaceEvent?
    @ObservedObject var viewModel: LiveViewModel

    var myKart: MyKartResponse { viewModel.myKart }

    private enum LogItem: Identifiable {
        case penalty(RacePenalty)
        case message(RaceMessage)

        var id: String {
            switch self {
            case .penalty(let penalty): return "pen_\(penalty.id)"
            case .message(let message): return "msg_\(message.id)"
            }
        }

        var date: Date {
            switch self {
            case .penalty(let penalty): return penalty.parsedDate ?? .distantPast
            case .message(let message): return message.parsedDate ?? .distantPast
            }
        }
    }

    private var combinedLog: [LogItem] {
        let penalties = myKart.penalties.map { LogItem.penalty($0) }
        let messages = myKart.messages.map { LogItem.message($0) }
        return (penalties + messages).sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id > $1.id
        }
    }

    @State private var showingBlueFlagCard = false
    @State private var processedBlueFlagIds: Set<Int> = []


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
                        
                        if let maxMinutes = event?.maxStintDuration, !myKart.isInPit {
                            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                                let duration = myKart.currentStintDuration
                                let maxSeconds = TimeInterval(maxMinutes * 60)
                                if duration >= (maxSeconds - 120) {
                                    stintWarningMessageCard(isOverTime: duration >= maxSeconds)
                                } else {
                                    EmptyView()
                                }
                            }
                        }

                        if event?.weightLimit != nil { weightCard }
                        if !combinedLog.isEmpty { penaltiesCard }
                        if combinedLog.isEmpty && activeFlag == nil { allClearCard }
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
                    || ($0.messageType == "custom" && ($0.text.lowercased() == "gara iniziata" || $0.text.lowercased() == "turno iniziato"))
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
                            .foregroundColor(.kartForeground)
                        Text("PESO E ZAVORRA")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartForeground)
                        Spacer()
                        Text("Min. \(minLimit, specifier: "%.1f") kg")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                    .padding(14)
                    .background(Color.kartForeground.opacity(0.04))

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
                                Divider().background(Color.kartBorder(opacity: 0.05)).padding(.leading, 14)
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
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.kartBorder(opacity: 0.06), lineWidth: 1))
            }
        }
    }

    private func driverSwapSection(members: [(name: String, weight: Double?)], minLimit: Double) -> some View {
        let currentDriver = members.first { $0.name == viewModel.driverSwap.current }
        let nextDriver = members.first { $0.name == viewModel.driverSwap.next }
        let currentBallast: Int = {
            guard let w = currentDriver?.weight else { return 0 }
            let diff = minLimit - w
            return diff > 0 ? Int(ceil(diff / 5.0)) * 5 : 0
        }()
        let nextBallast: Int = {
            guard let w = nextDriver?.weight else { return 0 }
            let diff = minLimit - w
            return diff > 0 ? Int(ceil(diff / 5.0)) * 5 : 0
        }()
        let delta = nextBallast - currentBallast  // positivo = aggiungere, negativo = togliere

        let bothKnown = currentDriver?.weight != nil && nextDriver?.weight != nil
        let sameDriver = viewModel.driverSwap.current == viewModel.driverSwap.next

        return VStack(spacing: 0) {
            Divider().background(Color.kartBorder(opacity: 0.08))

            VStack(spacing: 12) {
                // Header sezione
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.kartForeground)
                    Text("CAMBIO PILOTA")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartForeground)
                    Spacer()
                }

                // Picker affiancati
                HStack(spacing: 10) {
                    // Pilota attuale
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATTUALE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.kartDim)
                        Picker("Pilota attuale", selection: $viewModel.driverSwap.current) {
                            Text("Seleziona").tag(nil as String?)
                            ForEach(members.indices, id: \.self) { i in
                                Text(members[i].name).tag(Optional(members[i].name))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.kartForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.kartForeground.opacity(0.06))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1))
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
                        Picker("Pilota successivo", selection: $viewModel.driverSwap.next) {
                            Text("Seleziona").tag(nil as String?)
                            ForEach(members.indices, id: \.self) { i in
                                Text(members[i].name).tag(Optional(members[i].name))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.kartForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.kartForeground.opacity(0.06))
                        .cornerRadius(8)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity)
                }

                // Risultato cambio
                if currentDriver == nil || nextDriver == nil {
                    Text("Seleziona il pilota attuale e il successivo per calcolare il cambio zavorra.")
                        .font(.system(size: 12))
                        .foregroundColor(.kartDim)
                        .padding(.vertical, 6)
                } else if sameDriver {
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
                            .foregroundColor(.kartWarning)
                        Text("Peso mancante: impossibile calcolare")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.kartWarning)
                    }
                    .padding(.vertical, 6)
                } else if delta == 0 {
                    HStack(spacing: 10) {
                        Image(systemName: "equal.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.kartSuccess)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nessun cambio zavorra")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.kartForeground)
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
                            .foregroundColor(.kartWarning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isAdding ? "Aggiungi \(abs(delta)) kg" : "Togli \(abs(delta)) kg")
                                .font(.system(size: 16, weight: .black, design: .monospaced))
                                .foregroundColor(.kartWarning)
                            Text(isAdding ? "Aggiungere zavorra al kart" : "Rimuovere zavorra dal kart")
                                .font(.system(size: 11))
                                .foregroundColor(.kartDim)
                        }
                        Spacer()
                        // Zavorra finale del prossimo pilota
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(nextBallast) kg")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .foregroundColor(.kartForeground)
                            Text("zavorra totale")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.kartDim)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(14)
            .background(Color.kartForeground.opacity(0.025))
        }
    }

    private func weightMemberRow(name: String, weight: Double?, minLimit: Double) -> some View {
        let requiredWeight: Int = {
            guard let w = weight else { return -1 }
            let diff = minLimit - w
            return diff > 0 ? Int(ceil(diff / 5.0)) * 5 : 0
        }()

        let accentColor: Color = {
            if weight == nil { return .kartWarning }
            return requiredWeight > 0 ? .kartWarning : .kartSuccess
        }()

        return HStack(spacing: 12) {
            Image(systemName: weight == nil ? "exclamationmark.triangle.fill" : (requiredWeight > 0 ? "scalemass.fill" : "checkmark.seal.fill"))
                .font(.system(size: 18))
                .foregroundColor(accentColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.kartForeground)
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
                    .foregroundColor(.kartWarning)
            } else if requiredWeight > 0 {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("+\(requiredWeight) kg")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .foregroundColor(.kartWarning)
                    Text("zavorra")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartSecondaryText(opacity: 0.65))
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.kartSuccess)
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
                        .foregroundColor(.kartForeground)
                        .multilineTextAlignment(.center)
                        
                    if !myKart.teamMembers.isEmpty {
                        let memberNames = myKart.teamMembers.compactMap { $0.username }.joined(separator: " • ")
                        Text(memberNames)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.kartDim)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Divider().background(Color.kartBorder(opacity: 0.1))

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

                    Divider().background(Color.kartBorder(opacity: 0.1)).frame(height: 50)

                    TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                        let duration = myKart.currentStintDuration
                        let maxSeconds = (event?.maxStintDuration ?? 0) * 60
                        let isOverTime = maxSeconds > 0 && duration >= TimeInterval(maxSeconds)
                        let isWarningTime = maxSeconds > 0 && duration >= TimeInterval(maxSeconds - 120) && !isOverTime
                        let timerColor: Color = isOverTime ? .red : (isWarningTime ? .yellow : .kartForeground)

                        VStack(spacing: 4) {
                            Text(formatStint(duration))
                                .font(.system(size: 28, weight: .black, design: .monospaced))
                                .foregroundColor(timerColor)
                            HStack(spacing: 6) {
                                if myKart.isInPit {
                                    Text("PIT")
                                        .font(.system(size: 11, weight: .black, design: .monospaced))
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(Color.red.opacity(0.15))
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(Color.kartMessageBorder(.red, opacity: 0.5), lineWidth: 1))
                                } else {
                                    Text("STINT")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.kartDim)
                                }
                                
                                if let max = event?.maxStintDuration {
                                    Text("MAX \(max)'")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }

                    Divider().background(Color.kartBorder(opacity: 0.1)).frame(height: 50)

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
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.kartBorder(opacity: 0.06), lineWidth: 1))
    }

    private func formatStint(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "00:00"
    }

    // MARK: - Penalties Card

    @ViewBuilder
    private var penaltyWarningIcon: some View {
        if colorScheme == .light {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, Color.yellow)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
        }
    }

    private var penaltiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                penaltyWarningIcon
                    .font(.system(size: 11, weight: .bold))
                Text("PENALITÀ, AVVISI E MESSAGGI")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartPenaltyText)
                Spacer()
                Text("+\(myKart.totalPenaltySeconds)s totali")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.kartPenaltyText)
            }
            .padding(14)
            .background(Color.yellow.opacity(0.08))

            VStack(spacing: 0) {
                ForEach(combinedLog) { item in
                    switch item {
                    case .penalty(let penalty):
                        penaltyRow(penalty)
                    case .message(let message):
                        userMessageRow(message)
                    }
                }
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.kartMessageBorder(.orange, opacity: 0.2), lineWidth: 1))
    }

    private func penaltyRow(_ penalty: RacePenalty) -> some View {
        HStack(spacing: 12) {
            RacePenaltyIcon(penalty: penalty)
                .font(.system(size: 14))

            VStack(alignment: .leading, spacing: 2) {
                Text(penalty.displayLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.kartForeground)
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
            Divider().background(Color.kartBorder(opacity: 0.05)).padding(.leading, 40)
        }
    }

    private func userMessageRow(_ msg: RaceMessage) -> some View {
        let color = Color.kartRaceMessage(msg.messageType)

        return HStack(spacing: 12) {
            Image(systemName: msg.systemIcon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(msg.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.kartForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            if let date = msg.parsedDate {
                Text(date, style: .time)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.kartDim)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Divider().background(Color.kartBorder(opacity: 0.05)).padding(.leading, 30)
        }
    }

    // MARK: - All Clear

    private var allClearCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40))
                .foregroundColor(.kartSuccess)
            Text("Tutto OK!")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.kartForeground)
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
                .foregroundColor(.kartDim)
            Text("Nessun kart assegnato")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.kartDim)
            Text("Il Race Director non ha ancora assegnato un kart alla tua squadra.")
                .font(.system(size: 12))
                .foregroundColor(.kartDim)
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

    // MARK: - Stint Warning Message
    
    private func stintWarningMessageCard(isOverTime: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "timer")
                .font(.system(size: 24))
                .foregroundColor(isOverTime ? .red : .kartWarningText)
            VStack(alignment: .leading, spacing: 2) {
                Text(isOverTime ? "LIMITE STINT SUPERATO!" : "LIMITE TEMPO STINT")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(isOverTime ? .red : .kartWarningText)
                Text(isOverTime ? "Rientrare immediatamente ai box." : "Mancano meno di 2 minuti alla fine.")
                    .font(.system(size: 12))
                    .foregroundColor(.kartForeground)
            }
            Spacer()
        }
        .padding(16)
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isOverTime ? Color.kartMessageBorder(.red, opacity: 0.5) : Color.kartMessageBorder(.yellow, opacity: 0.5), lineWidth: 1))
    }
}
