import SwiftUI
import UIKit

// MARK: - Flag helpers

private extension RaceMessage {
    var flagFlashColor: Color? {
        switch messageType {
        case "yellow_flag": return .yellow
        case "red_flag":    return .red
        case "green_flag":  return .green
        default:            return nil
        }
    }

    var flagIcon: String? {
        switch messageType {
        case "yellow_flag", "red_flag", "green_flag": return "flag.fill"
        default: return nil
        }
    }

    var flagColor: Color? { flagFlashColor }

    var flagLabel: String {
        switch messageType {
        case "yellow_flag": return "GIALLA"
        case "red_flag":    return "ROSSA"
        case "green_flag":  return "VERDE"
        default:            return ""
        }
    }
}

// MARK: - PilotLiveView

/// Vista personale del pilota in gara.
/// Layout identico a PilotView (landscape locked) + flash bandiera + badge penalità.
struct PilotLiveView: View {
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var authState: AuthState

    var myKart: MyKartResponse { viewModel.myKart }

    // MARK: - Flash / Flag state
    @State private var flashColor: Color = .clear
    @State private var flashOpacity: Double = 0
    @State private var lastFlagMessageId: Int? = nil
    @State private var currentFlagMessage: RaceMessage? = nil

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

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
                    flagBadge
                    Spacer()
                    penaltyBadge
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                Spacer()
            }
        }
        .onChange(of: myKart.messages.last?.id) { _, _ in
            checkForNewFlag(messages: myKart.messages)
        }
        // ── Orientation lock (identico a PilotView) ────────────────────────
        .onAppear {
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

    private var dashboardView: some View {
        VStack(spacing: 30) {
            // Riga principale: kart number + tempi/penalità
            HStack(spacing: 30) {

                // Kart number (ruolo di "posizione" come P1 in PilotView)
                Text("#\(myKart.kartNumber ?? 0)")
                    .font(.system(size: 80, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 6) {
                    // Nome pilota (ruolo di "LAST LAP")
                    if let user = authState.currentUser {
                        let name = [user.firstName, user.lastName]
                            .compactMap { $0 }
                            .filter { !$0.isEmpty }
                            .joined(separator: " ")

                        VStack(alignment: .leading, spacing: -6) {
                            Text("PILOTA")
                                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                .foregroundColor(.kartDim)
                            Text(name.isEmpty ? "@\(user.username)" : name)
                                .font(.system(size: 46, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white)
                                .minimumScaleFactor(0.4)
                                .lineLimit(1)
                        }

                        // Username / team (ruolo di "BEST")
                        VStack(alignment: .leading, spacing: -2) {
                            Text("TEAM")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundColor(.kartDim)
                            Text(myKart.teamName ?? "@\(user.username)")
                                .font(.system(size: 24, weight: .heavy, design: .monospaced))
                                .foregroundColor(.kartAccent)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.top, 20)

            // Riga inferiore: penalità + ultimo messaggio
            // (ruolo delle gapCard in PilotView)
            HStack(spacing: 20) {
                // Card penalità totali
                if !myKart.penalties.isEmpty {
                    infoCard(
                        title: "PENALITÀ",
                        value: "+\(myKart.totalPenaltySeconds)s",
                        subtitle: "\(myKart.penalties.count) ricevute",
                        color: .orange,
                        icon: "exclamationmark.triangle.fill"
                    )
                }

                // Card ultimo messaggio
                if let latest = myKart.messages.last {
                    let color: Color = latest.flagColor ?? .cyan
                    infoCard(
                        title: "ULTIMO MESSAGGIO",
                        value: latest.text,
                        subtitle: nil,
                        color: color,
                        icon: latest.flagIcon ?? "megaphone.fill"
                    )
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Info Card (stile gapCard di PilotView)

    private func infoCard(
        title: String,
        value: String,
        subtitle: String?,
        color: Color,
        icon: String
    ) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
            }
            Text(value)
                .font(.system(size: 20, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.kartDim)
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

    // MARK: - Flag Badge (top-left HUD)

    @ViewBuilder
    private var flagBadge: some View {
        if let flagMsg = currentFlagMessage,
           let icon = flagMsg.flagIcon,
           let color = flagMsg.flagColor {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(color)
                Text(flagMsg.flagLabel)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
        }
    }

    // MARK: - Penalty Badge (top-right HUD)

    @ViewBuilder
    private var penaltyBadge: some View {
        if myKart.totalPenaltySeconds > 0 || !myKart.penalties.isEmpty {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.orange)
                Text("+\(myKart.totalPenaltySeconds)s")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(.orange)
                Text("(\(myKart.penalties.count))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.orange.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.orange.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.orange.opacity(0.35), lineWidth: 1))
        }
    }

    // MARK: - Flash Logic

    private func checkForNewFlag(messages: [RaceMessage]) {
        guard let latestFlag = messages.last(where: { $0.flagFlashColor != nil }) else { return }
        if latestFlag.id == lastFlagMessageId { return }

        lastFlagMessageId = latestFlag.id
        currentFlagMessage = latestFlag
        guard let color = latestFlag.flagFlashColor else { return }
        triggerFlash(color: color, flashIndex: 0)
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
}
