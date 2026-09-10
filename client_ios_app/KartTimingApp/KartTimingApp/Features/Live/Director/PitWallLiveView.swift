import SwiftUI
import Combine

struct PitWallLiveView: View {
    @ObservedObject var viewModel: LiveViewModel
    var event: RaceEvent?
    @EnvironmentObject var manager: KartTimingManager
    
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            VStack {
                if let timing = manager.timing, !timing.rows.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            if let max = event?.maxStintDuration {
                                HStack {
                                    Image(systemName: "timer")
                                    Text("Durata Massima Stint: \(max) min")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundColor(.orange)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                                .background(Color.orange.opacity(0.15))
                                .cornerRadius(8)
                            }
                            
                            ForEach(Array(timing.rows.enumerated()), id: \.offset) { idx, row in
                                if let kartNumStr = getKartNumber(from: row, headers: timing.headers),
                                   let kartNum = Int(kartNumStr) {
                                    
                                    let name = getDriverName(from: row, headers: timing.headers) ?? "Kart \(kartNum)"
                                    
                                    PitWallKartRow(
                                        kartNumber: kartNum,
                                        teamName: name,
                                        viewModel: viewModel,
                                        currentTime: currentTime,
                                        event: event
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.fetchAll()
                    }
                } else {
                    VStack {
                        Spacer()
                        Text("In attesa dei dati del live timing...")
                            .foregroundColor(.kartDim)
                        Spacer()
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func getKartNumber(from row: [String], headers: [String]) -> String? {
        let keywords = ["kart", "num", "n°", "no", "bib"]
        if let idx = headers.firstIndex(where: { h in keywords.contains(where: { h.lowercased().contains($0) }) }) {
            if idx < row.count { return row[idx] }
        }
        return nil
    }
    
    private func getDriverName(from row: [String], headers: [String]) -> String? {
        let keywords = ["driver", "pilota", "name", "nome", "pilot"]
        if let idx = headers.firstIndex(where: { h in keywords.contains(where: { h.lowercased().contains($0) }) }) {
            if idx < row.count { return row[idx] }
        }
        return nil
    }
}

struct PitWallKartRow: View {
    let kartNumber: Int
    let teamName: String
    @ObservedObject var viewModel: LiveViewModel
    let currentTime: Date
    var event: RaceEvent?
    
    @State private var isUpdating = false
    @State private var showError = false
    @State private var errorMsg = ""
    
    var assignment: LiveKartAssignment? {
        viewModel.kartAssignments.first(where: { $0.kartNumber == kartNumber })
    }
    
    var isInPit: Bool {
        assignment?.isInPit ?? false
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Number
            Text("#\(kartNumber)")
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundColor(.kartAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 80, alignment: .leading)
            
            // Name removed as requested
            
            Spacer()
            
            // Stint Time
            let duration = currentDuration()
            Text(formatStint(duration))
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(isInPit ? .red : .kartGreen)
                .frame(width: 70, alignment: .trailing)
            
            // Switch in pista / in pit
            if isUpdating {
                ProgressView()
                    .frame(width: 120)
            } else {
                Picker("Stato", selection: Binding(
                    get: { isInPit ? 1 : 0 },
                    set: { newValue in
                        let newIsInPit = newValue == 1
                        if newIsInPit != isInPit {
                            toggleStatus(to: newIsInPit)
                        }
                    }
                )) {
                    Text("Pista").tag(0)
                    Text("Pit").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.kartPanel)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isInPit ? Color.red.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .alert(isPresented: $showError) {
            Alert(title: Text("Errore"), message: Text(errorMsg), dismissButton: .default(Text("OK")))
        }
    }
    
    private func toggleStatus(to pitStatus: Bool) {
        Task {
            isUpdating = true
            do {
                try await viewModel.togglePitStatus(kartNumber: kartNumber, isInPit: pitStatus)
            } catch {
                errorMsg = error.localizedDescription
                showError = true
            }
            isUpdating = false
        }
    }
    
    private func currentDuration() -> TimeInterval {
        guard let a = assignment else { return 0 }
        var total = Double(a.stintElapsedSeconds)
        if let resumeDate = a.parsedStintLastResume, !a.isInPit {
            total += currentTime.timeIntervalSince(resumeDate)
        }
        return max(0, total)
    }
    
    private func formatStint(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: interval) ?? "00:00"
    }
}
