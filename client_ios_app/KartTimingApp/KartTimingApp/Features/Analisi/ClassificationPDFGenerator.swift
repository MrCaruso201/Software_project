import SwiftUI
import CoreGraphics

@available(iOS 16.0, *)
struct ClassificationPDFView: View {
    let event: RaceEvent
    let results: [EventResult]
    let lapStats: [LapStatsResponse]
    let penalties: [RacePenalty]
    let isTeamRace: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Text("RECAP GARA")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.gray)
                
                Text(event.title)
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                
                Text("\(event.location) • \(event.formattedDate)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.black.opacity(0.8))
            }
            .padding(.top, 40)
            .padding(.bottom, 20)
            
            Divider().background(Color.gray)
            
            // Results Table
            if isTeamRace {
                let teams = buildUniqueTeams(results)
                VStack(spacing: 12) {
                    ForEach(teams, id: \.teamName) { team in
                        HStack {
                            Text("\(team.position).")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 40, alignment: .leading)
                                .foregroundColor(.black)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(team.teamName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.black)
                                Text(team.members.map { $0.displayName }.joined(separator: ", "))
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(team.totalLaps) Giri")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.black)
                                if let gap = team.gap {
                                    Text(gap)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(results.sorted { ($0.position ?? 999) < ($1.position ?? 999) }) { result in
                        HStack {
                            Text("\(result.position ?? 0).")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 40, alignment: .leading)
                                .foregroundColor(.black)
                            
                            Text(result.displayName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.black)
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 2) {
                                if let lap = result.formattedBestLap {
                                    Text(lap)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.black)
                                }
                                if let gap = result.gap {
                                    Text(gap)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            
            if !lapStats.isEmpty {
                lapStatsSection
            }
            
            if !penalties.isEmpty {
                penaltiesSection
            }
            
            Spacer()
        }
        .padding(40)
        .frame(width: 600)
        .background(Color.white)
    }
    
    private var lapStatsSection: some View {
        VStack(spacing: 12) {
            Divider().background(Color.gray).padding(.top, 20)
            
            Text("STATISTICHE GIRI")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
            
            HStack {
                Text("KART/TEAM").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 150, alignment: .leading)
                Spacer()
                Text("BEST").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 80, alignment: .trailing)
                Text("WORST").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 80, alignment: .trailing)
                Text("MEDIA").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 80, alignment: .trailing)
                Text("GIRI").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 50, alignment: .trailing)
            }
            .padding(.vertical, 4)
            
            ForEach(lapStats.sorted { ($0.avgLapMs ?? 0) < ($1.avgLapMs ?? 0) }) { stat in
                HStack {
                    Text(teamName(forKart: stat.kartNumber) ?? "Kart #\(stat.kartNumber)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 150, alignment: .leading)
                    
                    Spacer()
                    
                    Text(formatMs(stat.bestLapMs))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(width: 80, alignment: .trailing)
                    
                    Text(formatMs(stat.worstLapMs))
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .trailing)
                        
                    Text(formatMs(stat.avgLapMs))
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .frame(width: 80, alignment: .trailing)
                        
                    Text("\(stat.lapsCounted)")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .frame(width: 50, alignment: .trailing)
                }
                Divider()
            }
        }
    }
    
    private var penaltiesSection: some View {
        VStack(spacing: 12) {
            Divider().background(Color.gray).padding(.top, 20)
            
            Text("STORICO PENALITÀ")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .center)
            
            HStack {
                Text("ORARIO").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 80, alignment: .leading)
                Text("KART/TEAM").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 150, alignment: .leading)
                Text("TIPO").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 120, alignment: .leading)
                Text("S.").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(width: 40, alignment: .trailing)
                Text("NOTE").font(.system(size: 12, weight: .bold)).foregroundColor(.black).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
            }
            .padding(.vertical, 4)
            
            ForEach(penalties.sorted { $0.createdAt < $1.createdAt }) { penalty in
                HStack(alignment: .top) {
                    Text(formatTime(penalty.createdAt))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.gray)
                        .frame(width: 80, alignment: .leading)
                    
                    Text(teamName(forKart: penalty.kartNumber) ?? "Kart #\(penalty.kartNumber)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 150, alignment: .leading)
                    
                    Text(formatPenaltyType(penalty.penaltyType))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .frame(width: 120, alignment: .leading)
                        
                    Text(penalty.seconds != nil ? "+\(penalty.seconds!)" : "")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 40, alignment: .trailing)
                        
                    Text(penalty.note ?? "")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
                Divider()
            }
        }
    }
    
    private func teamName(forKart kart: Int) -> String? {
        if let res = results.first(where: { $0.kartNumber == kart }) {
            return res.displayName
        }
        return nil
    }
    
    private func formatMs(_ ms: Int?) -> String {
        guard let ms = ms else { return "—" }
        let minutes = ms / 60_000
        let seconds = (ms % 60_000) / 1_000
        let millis  = ms % 1_000
        if minutes > 0 {
            return String(format: "%d:%02d.%03d", minutes, seconds, millis)
        } else {
            return String(format: "%d.%03d", seconds, millis)
        }
    }
    
    private func formatTime(_ isoString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS" // Adjust to actual length
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        
        var date = formatter.date(from: isoString)
        if date == nil {
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            date = formatter.date(from: isoString)
        }
        
        guard let d = date else { return isoString }
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        // Mostriamo l'ora locale del dispositivo
        timeFormatter.timeZone = TimeZone.current
        return timeFormatter.string(from: d)
    }
    
    private func formatPenaltyType(_ code: String) -> String {
        switch code {
        case "false_start": return "Falsa Partenza"
        case "track_limits": return "Track Limits"
        case "collision": return "Contatto"
        case "stint_time": return "Tempo Stint"
        case "pit_speed": return "Velocità Pit"
        default: return code.capitalized.replacingOccurrences(of: "_", with: " ")
        }
    }
    
    private func buildUniqueTeams(_ results: [EventResult]) -> [TeamResultGroup] {
        var dict: [String: [EventResult]] = [:]
        for r in results {
            let tName = r.teamName ?? "N/A"
            dict[tName, default: []].append(r)
        }
        var groups: [TeamResultGroup] = []
        for (name, members) in dict {
            if name == "N/A" { continue }
            let position = members.compactMap { $0.position }.min() ?? 999
            let totalLaps = members.compactMap { $0.laps }.max() ?? 0
            
            // find the member that has the best position to extract gap
            let bestMember = members.min { ($0.position ?? 999) < ($1.position ?? 999) }
            let gap = bestMember?.gap
            
            groups.append(TeamResultGroup(teamName: name, members: members, position: position, totalLaps: totalLaps, gap: gap))
        }
        groups.sort { $0.position < $1.position }
        return groups
    }
}

// Temporary model to group team members for PDF
struct TeamResultGroup {
    let teamName: String
    let members: [EventResult]
    let position: Int
    let totalLaps: Int
    let gap: String?
}

@available(iOS 16.0, *)
@MainActor
class ClassificationPDFGenerator {
    static func generatePDF(for event: RaceEvent, results: [EventResult], lapStats: [LapStatsResponse], penalties: [RacePenalty], isTeamRace: Bool) -> URL? {
        let pdfView = ClassificationPDFView(event: event, results: results, lapStats: lapStats, penalties: penalties, isTeamRace: isTeamRace)
        let renderer = ImageRenderer(content: pdfView)
        
        let safeName = event.title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Classifica_\(safeName).pdf")
        
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            
            pdfContext.beginPDFPage(nil)
            context(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
        }
        return url
    }
}

// Wrapper for UIActivityViewController to share the PDF
struct PDFShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
