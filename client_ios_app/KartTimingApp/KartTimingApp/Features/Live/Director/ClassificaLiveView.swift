import SwiftUI

/// Vista Classifica Live per il Race Director.
/// Mostra la classifica proveniente dal WebSocket esistente,
/// con una colonna aggiuntiva per le penalità totali di ogni kart.
struct ClassificaLiveView: View {
    @ObservedObject var viewModel: LiveViewModel

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header colonne
                HStack(spacing: 0) {
                    Text("POS").frame(width: 36).foregroundColor(.kartDim)
                    Text("KART").frame(width: 50).foregroundColor(.kartDim)
                    Text("SQUADRA").frame(maxWidth: .infinity, alignment: .leading).foregroundColor(.kartDim)
                    Text("PEN.").frame(width: 54).foregroundColor(.kartDim)
                }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.kartPanel)

                if viewModel.kartAssignments.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "list.number")
                            .font(.system(size: 40))
                            .foregroundColor(.kartDim.opacity(0.4))
                        Text("Classifica non disponibile")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.kartDim)
                        Text("Assegna i kart ai team per vedere la classifica live.")
                            .font(.system(size: 12))
                            .foregroundColor(.kartDim.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(Array(viewModel.kartAssignments.sorted(by: { $0.kartNumber < $1.kartNumber }).enumerated()), id: \.element.id) { index, assignment in
                                classificaRow(position: index + 1, assignment: assignment)
                            }
                        }
                    }
                }
            }
        }
    }

    private func classificaRow(position: Int, assignment: LiveKartAssignment) -> some View {
        let totalSec = viewModel.totalPenaltySeconds(for: assignment.kartNumber)
        let penCount = viewModel.penaltiesByKart[assignment.kartNumber]?.count ?? 0

        return HStack(spacing: 0) {
            // Posizione
            Text("\(position)")
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(position == 1 ? .kartAccent : .white)
                .frame(width: 36)

            // Kart number
            Text("#\(assignment.kartNumber)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(.kartAccent)
                .frame(width: 50)

            // Team name
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.teamName ?? "Team \(assignment.kartNumber)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Penalità
            if penCount > 0 {
                VStack(spacing: 2) {
                    Text("+\(totalSec)s")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .foregroundColor(.orange)
                    Text("\(penCount)×")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.orange.opacity(0.7))
                }
                .frame(width: 54)
            } else {
                Text("—")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.kartDim.opacity(0.4))
                    .frame(width: 54)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(position % 2 == 0 ? Color.kartPanel : Color.kartBG)
        .overlay(alignment: .bottom) {
            Divider().background(Color.white.opacity(0.04))
        }
    }
}
