import SwiftUI
import CoreGraphics

@available(iOS 16.0, *)
struct ClassificationPDFView: View {
    let event: RaceEvent
    let results: [EventResult]
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
            
            Spacer()
        }
        .padding(40)
        .frame(width: 600)
        .background(Color.white)
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
    static func generatePDF(for event: RaceEvent, results: [EventResult], isTeamRace: Bool) -> URL? {
        let pdfView = ClassificationPDFView(event: event, results: results, isTeamRace: isTeamRace)
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
