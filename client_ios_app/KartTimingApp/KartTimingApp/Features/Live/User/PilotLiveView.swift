import SwiftUI

/// Pilot View — vista personale del pilota nell'ambito del proprio team/kart.
/// Stesso kart del team, ma con focus sull'esperienza individuale.
struct PilotLiveView: View {
    @ObservedObject var viewModel: LiveViewModel
    @EnvironmentObject var authState: AuthState

    var myKart: MyKartResponse { viewModel.myKart }

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if myKart.kartNumber == nil {
                noKartState
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        pilotHeroCard
                        statusCard
                        if !myKart.penalties.isEmpty { compactPenaltiesCard }
                        if !myKart.messages.isEmpty { latestMessageCard }
                    }
                    .padding(16)
                    .padding(.bottom, 30)
                }
            }
        }
    }

    // MARK: - Pilot Hero Card

    private var pilotHeroCard: some View {
        VStack(spacing: 14) {
            // Avatar pilota
            ZStack {
                Circle()
                    .fill(Color.kartAccent.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.kartAccent)
            }

            VStack(spacing: 4) {
                if let user = authState.currentUser {
                    let name = [user.firstName, user.lastName]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    Text(name.isEmpty ? "@\(user.username)" : name)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                    if !name.isEmpty {
                        Text("@\(user.username)")
                            .font(.system(size: 13))
                            .foregroundColor(.kartDim)
                    }
                }

                HStack(spacing: 8) {
                    Text(myKart.teamName ?? "Team")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.kartDim)
                    Text("·")
                        .foregroundColor(.kartDim)
                    Text("Kart #\(myKart.kartNumber ?? 0)")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.kartAccent)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.kartPanel)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [Color.kartAccent.opacity(0.4), Color.kartAccent.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Status Card (penalità cumulative)

    private var statusCard: some View {
        HStack(spacing: 0) {
            statBlock(
                icon: "exclamationmark.triangle.fill",
                value: "\(myKart.penalties.count)",
                label: "Penalità",
                color: myKart.penalties.isEmpty ? .kartDim : .orange
            )

            Divider().background(Color.white.opacity(0.08)).frame(height: 40)

            statBlock(
                icon: "clock.fill",
                value: "+\(myKart.totalPenaltySeconds)s",
                label: "Secondi totali",
                color: myKart.totalPenaltySeconds > 0 ? .orange : .kartDim
            )

            Divider().background(Color.white.opacity(0.08)).frame(height: 40)

            statBlock(
                icon: "bubble.left.fill",
                value: "\(myKart.messages.count)",
                label: "Messaggi",
                color: myKart.messages.isEmpty ? .kartDim : .cyan
            )
        }
        .padding(.vertical, 12)
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.05), lineWidth: 1))
    }

    private func statBlock(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(color)
            Text(value)
                .font(.system(size: 20, weight: .black, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.kartDim)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Compact Penalties

    private var compactPenaltiesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.orange)
                Text("LE TUE PENALITÀ")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.orange)
                Spacer()
            }
            .padding(12)
            .background(Color.orange.opacity(0.08))

            ForEach(myKart.penalties) { penalty in
                HStack {
                    Text(penalty.displayLabel)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    if let date = penalty.parsedDate {
                        Text(date, style: .time)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.kartDim)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) {
                    Divider().background(Color.white.opacity(0.05)).padding(.leading, 14)
                }
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Latest Message

    private var latestMessageCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 11, weight: .bold)).foregroundColor(.cyan)
                Text("ULTIMO MESSAGGIO")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(.cyan)
                Spacer()
                Text("\(myKart.messages.count) totali")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.kartDim)
            }
            .padding(12)
            .background(Color.cyan.opacity(0.08))

            if let latest = myKart.messages.last {
                Text(latest.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
            }
        }
        .background(Color.kartPanel)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.2), lineWidth: 1))
    }

    // MARK: - No Kart

    private var noKartState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.slash").font(.system(size: 52)).foregroundColor(.kartDim.opacity(0.4))
            Text("Kart non ancora assegnato")
                .font(.system(size: 16, weight: .bold)).foregroundColor(.kartDim)
            Text("Attendi che il Race Director assegni un numero kart alla tua squadra.")
                .font(.system(size: 12)).foregroundColor(.kartDim.opacity(0.6)).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
