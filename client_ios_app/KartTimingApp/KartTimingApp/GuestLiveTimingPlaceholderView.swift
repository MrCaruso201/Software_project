import SwiftUI

// ---------------------------------------------------------------------------
// Schermata placeholder per "Live Timing senza accesso"
// ---------------------------------------------------------------------------

struct GuestLiveTimingPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "eye.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.08, green: 0.45, blue: 0.95),
                                     Color(red: 0.0,  green: 0.75, blue: 0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Live Timing")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(.white)

                Text("Modalità ospite")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.kartDim)

                Spacer()

                Text("Schermata in arrivo…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.kartDim.opacity(0.5))
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 30)
        }
        .navigationTitle("Live Timing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
