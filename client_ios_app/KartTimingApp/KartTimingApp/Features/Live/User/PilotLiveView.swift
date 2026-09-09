import SwiftUI
import UIKit

// MARK: - Flag helpers

private extension RaceMessage {
    var flagFlashColor: Color? {
        switch messageType {
        case "yellow_flag": return .yellow
        case "red_flag":    return .red
        case "green_flag":  return .green
        case "checkered_flag": return .white
        case "custom" where text.lowercased() == "gara iniziata": return .green
        default:            return nil
        }
    }

    var flagIcon: String? {
        switch messageType {
        case "yellow_flag", "red_flag", "green_flag": return "flag.fill"
        case "custom" where text.lowercased() == "gara iniziata": return "flag.fill"
        case "checkered_flag": return "flag.checkered.2.crossed"
        default: return nil
        }
    }

    var flagColor: Color? {
        switch messageType {
        case "checkered_flag": return .black // In the badge, white bg means black text/icon is better, but badge background is based on color.opacity(0.25). We'll handle this in flagBadge itself or return white here and adjust badge. Wait, if we return .white, text will be white on white. Let's return .white and fix badge, or return .black for checkered. Actually, checkered is better as .white and we can handle it in the view, but let's just return .white for now.
        default: return flagFlashColor
        }
    }

    var flagLabel: String {
        switch messageType {
        case "yellow_flag": return "GIALLA"
        case "red_flag":    return "ROSSA"
        case "green_flag":  return "VERDE"
        case "checkered_flag": return "A SCACCHI"
        case "custom" where text.lowercased() == "gara iniziata": return "IN CORSO"
        default:            return ""
        }
    }
}

// MARK: - PilotLiveView

/// Vista personale del pilota in gara.
/// Layout identico a PilotView (landscape locked) + flash bandiera + badge penalità.
struct PilotLiveView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var manager: KartTimingManager

    var myKart: MyKartResponse { viewModel.myKart }

    // MARK: - Flash / Flag state
    @State private var flashColor: Color = .clear
    @State private var flashOpacity: Double = 0
    @State private var lastFlagMessageId: Int? = nil

    @State private var showingBlueFlagScreen = false
    @State private var processedBlueFlagIds: Set<Int> = []

    @State private var showingDropPositionScreen = false
    @State private var processedDropPositionIds: Set<Int> = []

    @State private var showingTextMessage = false
    @State private var currentTextMessage: RaceMessage? = nil
    @State private var processedTextMessageIds: Set<Int> = []

    private var hasBlackFlag: Bool {
        myKart.penalties.contains(where: { $0.penaltyType == "black_flag" })
    }

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

    private var isGlobalRedFlag: Bool {
        currentFlagMessage?.messageType == "red_flag"
    }
    
    private var isGlobalYellowFlag: Bool {
        currentFlagMessage?.messageType == "yellow_flag"
    }
    
    private var isGaraIniziata: Bool {
        guard let msg = currentFlagMessage else { return false }
        return msg.messageType == "green_flag" || (msg.messageType == "custom" && msg.text.lowercased() == "gara iniziata")
    }
    
    private var hasLapTimes: Bool {
        guard let timing = manager.timing, let kartNum = myKart.kartNumber else { return false }
        let h = timing.headers
        let kartIdx = colIndex(in: h, keywords: ["kart", "num", "n°", "no", "bib"])
        let lapIdx  = colIndex(in: h, keywords: ["last", "lap", "giro", "time", "tempo"])
        
        if let kIdx = kartIdx, let pilotRowIdx = timing.rows.firstIndex(where: { $0.indices.contains(kIdx) && $0[kIdx] == String(kartNum) }) {
            let pilotRow = timing.rows[pilotRowIdx]
            let lapTime = (lapIdx != nil && lapIdx! < pilotRow.count) ? pilotRow[lapIdx!] : "-"
            return lapTime != "-"
        }
        return false
    }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if showingTextMessage {
                textMessageState
            } else if showingDropPositionScreen {
                dropPositionState
            } else if showingBlueFlagScreen {
                blueFlagState
            } else if hasBlackFlag {
                blackFlagState
            } else if isGlobalRedFlag {
                redFlagState
            } else if isGlobalYellowFlag {
                yellowFlagState
            } else if isGaraIniziata && !hasLapTimes && myKart.kartNumber != nil {
                greenFlagState
            } else {
                if myKart.kartNumber == nil {
                    noKartState
                } else {
                    dashboardView
                }

                // Flash overlay
                flashColor
                    .opacity(flashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // HUD badges (flag top-left, penalty top-right)
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            flagBadge
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 12) {
                            penaltyBadge
                            stintBadge
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer()
                }
            }
        }
        .navigationTitle("Vista Pilota")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.kartAccent)
                }
            }
        }
        .onChange(of: myKart.messages.last?.id) { _, _ in
            checkForNewFlag(messages: myKart.messages)
            checkForNewTextMessage(messages: myKart.messages)
        }
        .onChange(of: myKart.penalties.count) { _, _ in
            checkForNewBlueFlags()
            checkForNewDropPosition()
        }
        // ── Orientation lock (identico a PilotView) ────────────────────────
        .onAppear {
            checkForNewBlueFlags()
            checkForNewDropPosition()
            checkForNewTextMessage(messages: myKart.messages)
            
            if let latestFlag = myKart.messages.last(where: { $0.flagFlashColor != nil }) {
                lastFlagMessageId = latestFlag.id
            }

            AppDelegate.orientationLock = .landscapeRight
            UIDevice.current.setValue(
                UIInterfaceOrientation.landscapeRight.rawValue,
                forKey: "orientation"
            )
            if #available(iOS 16.0, *) {
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                windowScene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            } else {
                UINavigationController.attemptRotationToDeviceOrientation()
            }
        }
        .onDisappear {
            AppDelegate.orientationLock = .portrait
            UIDevice.current.setValue(
                UIInterfaceOrientation.portrait.rawValue,
                forKey: "orientation"
            )
            if #available(iOS 16.0, *) {
                let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                windowScene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            } else {
                UINavigationController.attemptRotationToDeviceOrientation()
            }
        }
    }

    // MARK: - Dashboard (identico strutturalmente a PilotView)

    @ViewBuilder
    private var dashboardView: some View {
        if let timing = manager.timing, let kartNum = myKart.kartNumber {
            let h = timing.headers
            let posIdx  = colIndex(in: h, keywords: ["pos", "pos.", "p", "#"]) ?? 0
            let kartIdx = colIndex(in: h, keywords: ["kart", "num", "n°", "no", "bib"])
            let nameIdx = colIndex(in: h, keywords: ["driver", "pilota", "name", "nome", "pilot"])
            let lapIdx  = colIndex(in: h, keywords: ["last", "lap", "giro", "time", "tempo"])
            let bestIdx = colIndex(in: h, keywords: ["best", "migliore", "fastest", "record"])
            let gapIdx  = colIndex(in: h, keywords: ["gap", "diff", "distanza", "behind"])

            if let kIdx = kartIdx, let pilotRowIdx = timing.rows.firstIndex(where: { $0.indices.contains(kIdx) && $0[kIdx] == String(kartNum) }) {
                
                let pilotRow = timing.rows[pilotRowIdx]
                let pos = posIdx < pilotRow.count ? pilotRow[posIdx] : "-"
                let lapTime = (lapIdx != nil && lapIdx! < pilotRow.count) ? pilotRow[lapIdx!] : "-"
                let bestTime = (bestIdx != nil && bestIdx! < pilotRow.count) ? pilotRow[bestIdx!] : "-"
                let isPersonalBest = lapTime != "-" && lapTime == bestTime
                
                VStack(spacing: 30) {
                    // Posizione e Tempi
                    HStack(spacing: 30) {
                        Text("P\(pos)")
                            .font(.system(size: 80, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            // LAST LAP (più visibile)
                            VStack(alignment: .leading, spacing: -6) {
                                Text("LAST LAP")
                                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.kartDim)
                                Text(lapTime)
                                    .font(.system(size: 46, weight: .heavy, design: .monospaced))
                                    .foregroundColor(isPersonalBest ? .kartGreen : .white)
                            }
                            
                            // BEST LAP (più piccolo, in verde)
                            VStack(alignment: .leading, spacing: -2) {
                                Text("BEST")
                                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.kartDim)
                                Text(bestTime)
                                    .font(.system(size: 24, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.kartGreen)
                            }
                        }
                    }
                    .padding(.top, 20)

                    // Distacchi (Davanti e Dietro)
                    HStack(spacing: 20) {
                        // Davanti (nascosto se primo)
                        if pilotRowIdx > 0 {
                            let aheadRow = timing.rows[pilotRowIdx - 1]
                            let aheadName = (nameIdx != nil && nameIdx! < aheadRow.count) ? aheadRow[nameIdx!] : "Pilota"
                            let aheadGap = (gapIdx != nil && gapIdx! < pilotRow.count) ? pilotRow[gapIdx!] : "-"
                            gapCard(name: aheadName, gap: aheadGap, isAhead: true)
                        }

                        // Dietro (nascosto se ultimo)
                        if pilotRowIdx < timing.rows.count - 1 {
                            let behindRow = timing.rows[pilotRowIdx + 1]
                            let behindName = (nameIdx != nil && nameIdx! < behindRow.count) ? behindRow[nameIdx!] : "Pilota"
                            let behindGap = (gapIdx != nil && gapIdx! < behindRow.count) ? behindRow[gapIdx!] : "-"
                            gapCard(name: behindName, gap: behindGap, isAhead: false)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.kartRed)
                    Text("Kart #\(kartNum) non in pista")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Text("Attendi che il kart completi un giro...")
                        .font(.system(size: 14))
                        .foregroundColor(.kartDim)
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("In attesa del live timing...")
                    .font(.system(size: 14))
                    .foregroundColor(.kartDim)
                    .padding(.top, 8)
            }
        }
    }

    private func gapCard(name: String, gap: String, isAhead: Bool) -> some View {
        VStack(spacing: 8) {
            Text(name)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: isAhead ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isAhead ? .kartRed : .kartGreen)
                Text(gap)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(isAhead ? .kartRed : .kartGreen)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.black.opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    private func colIndex(in headers: [String], keywords: [String]) -> Int? {
        for kw in keywords {
            if let i = headers.firstIndex(where: { $0.lowercased().contains(kw) }) {
                return i
            }
        }
        return nil
    }

    // MARK: - Flag Badge (top-left HUD)

    @ViewBuilder
    private var flagBadge: some View {
        if let flagMsg = currentFlagMessage,
           let icon = flagMsg.flagIcon,
           let color = flagMsg.flagColor {
            if !(isGaraIniziata && hasLapTimes) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .heavy))
                        .foregroundColor(color)
                    Text(flagMsg.flagLabel)
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .foregroundColor(color)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(color.opacity(0.25))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 2))
            }
        }
    }

    // MARK: - Penalty Badge (top-right HUD)

    @ViewBuilder
    private var penaltyBadge: some View {
        if myKart.totalPenaltySeconds > 0 || !myKart.penalties.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.orange)
                Text("+\(myKart.totalPenaltySeconds)s")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundColor(.orange)
                Text("(\(myKart.actualPenalties.count))")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.2))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.orange.opacity(0.6), lineWidth: 2))
        }
    }

    // MARK: - Stint Badge

    @ViewBuilder
    private var stintBadge: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            HStack(spacing: 8) {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(myKart.isInPit ? .red : .kartGreen)
                Text(formatStint(myKart.currentStintDuration))
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .foregroundColor(myKart.isInPit ? .red : .white)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.4))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 2))
        }
    }

    private func formatStint(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "00:00"
    }

    // MARK: - Flash Logic

    private func checkForNewFlag(messages: [RaceMessage]) {
        guard let latestFlag = messages.last(where: { $0.flagFlashColor != nil }) else { return }
        if latestFlag.id == lastFlagMessageId { return }

        lastFlagMessageId = latestFlag.id
        guard let color = latestFlag.flagFlashColor else { return }
        triggerFlash(color: color, flashIndex: 0)
    }

    private func checkForNewBlueFlags() {
        for penalty in myKart.penalties where penalty.penaltyType == "blue_flag" {
            if !processedBlueFlagIds.contains(penalty.id) {
                processedBlueFlagIds.insert(penalty.id)
                
                let age = penalty.parsedDate.map { Date().timeIntervalSince($0) } ?? 0
                if age < 5 {
                    showingBlueFlagScreen = true
                    let remainingTime = 5 - age
                    DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) {
                        showingBlueFlagScreen = false
                    }
                }
            }
        }
    }

    private func checkForNewDropPosition() {
        for penalty in myKart.penalties where penalty.penaltyType == "drop_position" {
            if !processedDropPositionIds.contains(penalty.id) {
                processedDropPositionIds.insert(penalty.id)
                
                let age = penalty.parsedDate.map { Date().timeIntervalSince($0) } ?? 0
                if age < 10 {
                    showingDropPositionScreen = true
                    let remainingTime = 10 - age
                    DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) {
                        showingDropPositionScreen = false
                    }
                }
            }
        }
    }

    private func triggerFlash(color: Color, flashIndex: Int) {
        guard flashIndex < 3 else { return }
        flashColor = color
        withAnimation(.easeIn(duration: 0.15)) { flashOpacity = 0.55 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.2)) { flashOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                triggerFlash(color: color, flashIndex: flashIndex + 1)
            }
        }
    }

    private func checkForNewTextMessage(messages: [RaceMessage]) {
        guard let latestMsg = messages.last, 
              (latestMsg.messageType == "info" || latestMsg.messageType == "custom") else { return }
        
        if !processedTextMessageIds.contains(latestMsg.id) {
            processedTextMessageIds.insert(latestMsg.id)
            
            let age = latestMsg.parsedDate.map { Date().timeIntervalSince($0) } ?? 0
            if age < 20 {
                currentTextMessage = latestMsg
                withAnimation {
                    showingTextMessage = true
                }
                
                let remainingTime = 20 - age
                DispatchQueue.main.asyncAfter(deadline: .now() + remainingTime) {
                    if currentTextMessage?.id == latestMsg.id {
                        withAnimation {
                            showingTextMessage = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - No Kart

    private var noKartState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash")
                .font(.system(size: 52))
                .foregroundColor(.kartDim.opacity(0.4))
            Text("Kart non ancora assegnato")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.kartDim)
            Text("Attendi che il Race Director assegni un numero kart alla tua squadra.")
                .font(.system(size: 12))
                .foregroundColor(.kartDim.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }

    // MARK: - Black Flag State

    private var blackFlagState: some View {
        ZStack {
            Color.red.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 90))
                    .foregroundColor(.black)
                
                Text("TORNARE AI BOX")
                    .font(.system(size: 70, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                
                Text("BANDIERA NERA")
                    .font(.system(size: 50, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .padding(40)
        }
    }
    
    // MARK: - Red Flag State

    private var redFlagState: some View {
        ZStack {
            Color.red.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 90))
                    .foregroundColor(.white)
                
                Text("RIENTRARE AI BOX")
                    .font(.system(size: 70, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                
                Text("BANDIERA ROSSA")
                    .font(.system(size: 50, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .padding(40)
        }
    }
    
    // MARK: - Yellow Flag State

    private var yellowFlagState: some View {
        ZStack {
            Color.yellow.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 90))
                    .foregroundColor(.black)
                
                Text("ATTENZIONE")
                    .font(.system(size: 70, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                
                Text("BANDIERA GIALLA")
                    .font(.system(size: 50, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .padding(40)
        }
    }
    
    // MARK: - Blue Flag State

    private var blueFlagState: some View {
        ZStack {
            Color.blue.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 90))
                    .foregroundColor(.white)
                
                Text("LASCIARE SPAZIO")
                    .font(.system(size: 70, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                
                Text("BANDIERA BLU")
                    .font(.system(size: 50, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .padding(40)
        }
    }

    // MARK: - Drop Position State

    private var dropPositionState: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 90))
                    .foregroundColor(.black)
                
                Text("PENALITÀ")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.7))
                
                Text("DROP 1 POSITION")
                    .font(.system(size: 70, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(40)
        }
    }
    
    // MARK: - Text Message State

    private var textMessageState: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(currentTextMessage?.isBroadcast == true ? "MESSAGGIO BROADCAST" : "MESSAGGIO")
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(.black.opacity(0.7))
                
                Text(currentTextMessage?.text ?? "")
                    .font(.system(size: 60, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
            .padding(40)
        }
    }
    
    // MARK: - Green Flag State

    private var greenFlagState: some View {
        ZStack {
            Color.kartGreen.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "flag.fill")
                    .font(.system(size: 90))
                    .foregroundColor(.black)
                
                Text("GARA INIZIATA")
                    .font(.system(size: 70, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                
                Text("BUONA GARA!")
                    .font(.system(size: 50, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
            }
            .padding(40)
        }
    }
}
