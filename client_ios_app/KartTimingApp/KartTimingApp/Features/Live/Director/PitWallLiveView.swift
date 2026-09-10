import SwiftUI

struct PitWallLiveView: View {
    @ObservedObject var viewModel: LiveViewModel
    var event: RaceEvent?
    @EnvironmentObject var manager: KartTimingManager
    

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()
            
            VStack {
                if let timing = manager.timing, !timing.rows.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 8) {
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
                            
                            ForEach(timing.displayRows) { item in
                                let row = item.values
                                if let kartNumStr = getKartNumber(from: row, headers: timing.headers),
                                   let kartNum = Int(kartNumStr) {
                                    
                                    let name = getDriverName(from: row, headers: timing.headers) ?? "Kart \(kartNum)"
                                    
                                    PitWallKartRow(
                                        kartNumber: kartNum,
                                        teamName: name,
                                        viewModel: viewModel,
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
            StintClock(assignment: assignment, event: event)
            
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
                .stroke(isInPit ? Color.red.opacity(0.5) : Color.kartBorder(opacity: 0.1), lineWidth: 1)
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
    
}

private struct StintClock: View {
    let assignment: LiveKartAssignment?
    var event: RaceEvent?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: assignment?.isInPit != false)) { context in
            let duration = getDuration(at: context.date)
            let maxSeconds = (event?.maxStintDuration ?? 0) * 60
            let isOverTime = maxSeconds > 0 && duration >= TimeInterval(maxSeconds)
            let isWarningTime = maxSeconds > 0 && duration >= TimeInterval(maxSeconds - 120) && !isOverTime
            
            let color: Color = {
                if assignment?.isInPit == true { return .red }
                if isOverTime { return .red }
                if isWarningTime { return .yellow }
                return .kartGreen
            }()
            
            Text(formattedDuration(duration))
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 70, alignment: .trailing)
        }
    }
    
    private func getDuration(at date: Date) -> TimeInterval {
        guard let assignment else { return 0 }
        var duration = Double(assignment.stintElapsedSeconds)
        if !assignment.isInPit, let resume = assignment.parsedStintLastResume {
            duration += date.timeIntervalSince(resume)
        }
        return max(0, duration)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
