import SwiftUI
import UIKit
import Combine

struct TimingPilotView: View {
    @StateObject private var gpsSpeed = GPSSpeedMonitor()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authState: AuthState
    @EnvironmentObject var manager: KartTimingManager

    @State private var pilotName: String = ""
    @State private var isNameConfirmed: Bool = false
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.kartBG.ignoresSafeArea()

            if isNameConfirmed {
                dashboardView
            } else {
                // Schermata di inserimento nome pilota
                VStack(spacing: 24) {
                    Spacer()
                    
                    VStack(spacing: 8) {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(.kartAccent)
                        Text("Ricerca Pilota")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.kartForeground)
                        Text("Inserisci il nome del pilota di cui vuoi acquisire il live timing.")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundColor(.kartDim)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("ATTENZIONE: È fondamentale inserire il nome esatto così come appare sul monitor del kartodromo!")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.kartRed)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 4)
                    }
                    
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.kartDim)
                            TextField("Nome pilota...", text: $pilotName)
                                .foregroundColor(.kartForeground)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.words)
                        }
                        .padding(14)
                        .background(Color.kartPanel)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
                        )
                        .frame(maxWidth: 350)
                        
                        Button {
                            if !pilotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                withAnimation {
                                    isNameConfirmed = true
                                }
                            }
                        } label: {
                            Text("Conferma")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: 350)
                                .padding(.vertical, 14)
                                .background(pilotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.kartAccent)
                                .cornerRadius(10)
                        }
                        .disabled(pilotName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    Spacer()
                }
            }
        }
        .navigationTitle(isNameConfirmed ? "" : "Vista Pilota")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if isNameConfirmed {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 10) {
                        Image(systemName: "speedometer")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.kartAccent)
                        Text(gpsSpeed.speedKmh.map { String(format: "%.0f", $0) } ?? "—")
                            .font(.system(size: 34, weight: .black, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                        VStack(alignment: .leading, spacing: 0) {
                            Text("km/h").font(.system(size: 12, weight: .bold))
                            Text(gpsSpeed.status).font(.system(size: 10))
                                .foregroundColor(.kartDim)
                        }
                    }
                    .foregroundColor(.kartForeground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color.kartPanel, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .combine)
                }
            }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { gpsSpeed.start() } else { gpsSpeed.stop() }
        }
        .onReceive(timer) { _ in
            gpsSpeed.expireSample()
        }
        .onAppear {
            gpsSpeed.start()
            // Mantiene accesa la dashboard durante la guida.
            UIApplication.shared.isIdleTimerDisabled = true
            // Forza orientamento landscape FISSO (solo destra, non ruota a 180°)
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
            gpsSpeed.stop()
            // Riabilita il blocco automatico quando si esce dalla vista pilota.
            UIApplication.shared.isIdleTimerDisabled = false
            // Ripristina portrait
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

    // ── DASHBOARD VIEW ────────────────────────────────────────────────────────

    @ViewBuilder
    private var dashboardView: some View {
        if let timing = manager.timing {
            let h = timing.headers
            let posIdx  = colIndex(in: h, keywords: ["pos", "pos.", "p", "#"]) ?? 0
            let nameIdx = colIndex(in: h, keywords: ["driver", "pilota", "name", "nome", "pilot"])
            let lapIdx  = colIndex(in: h, keywords: ["last", "lap", "giro", "time", "tempo"])
            let bestIdx = colIndex(in: h, keywords: ["best", "migliore", "fastest", "record"])
            let gapIdx  = colIndex(in: h, keywords: ["gap", "diff", "distanza", "behind"])

            if let nameI = nameIdx, let pilotRowIdx = timing.rows.firstIndex(where: { $0.indices.contains(nameI) && $0[nameI].localizedCaseInsensitiveContains(pilotName) }) {
                
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
                            .foregroundColor(.kartForeground)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            // LAST LAP (più visibile)
                            VStack(alignment: .leading, spacing: -6) {
                                Text("LAST LAP")
                                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.kartDim)
                                Text(lapTime)
                                    .font(.system(size: 46, weight: .heavy, design: .monospaced))
                                    .foregroundColor(isPersonalBest ? .kartGreen : .kartForeground)
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
                            let aheadName = aheadRow[nameI]
                            let aheadGap = (gapIdx != nil && gapIdx! < pilotRow.count) ? pilotRow[gapIdx!] : "-"
                            gapCard(name: aheadName, gap: aheadGap, isAhead: true)
                        }

                        // Dietro (nascosto se ultimo)
                        if pilotRowIdx < timing.rows.count - 1 {
                            let behindRow = timing.rows[pilotRowIdx + 1]
                            let behindName = behindRow[nameI]
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
                    Text("Pilota non trovato")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.kartForeground)
                    Text("In attesa che '\(pilotName)' scenda in pista...")
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
                .foregroundColor(.kartForeground)
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
        .background(Color.kartInset.opacity(0.3))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.kartBorder(opacity: 0.1), lineWidth: 1)
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
}
