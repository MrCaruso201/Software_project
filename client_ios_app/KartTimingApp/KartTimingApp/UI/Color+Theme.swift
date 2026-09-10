import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appTheme"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Chiaro"
        case .dark: return "Scuro"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

extension Color {
    static let kartBG      = adaptive(light: UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1),
                                      dark: UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1))
    static let kartPanel   = adaptive(light: .white,
                                      dark: UIColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1))
    static let kartAccent  = Color(red: 0.96, green: 0.14, blue: 0.21)   // rosso
    static let kartGreen   = Color(red: 0.13, green: 0.76, blue: 0.37)
    static let kartRed     = Color(red: 0.93, green: 0.27, blue: 0.27)
    static let kartDim     = adaptive(light: UIColor.black.withAlphaComponent(0.68),
                                      dark: UIColor.white.withAlphaComponent(0.35))

    // Testi, bordi e superfici neutre seguono il tema di sistema.
    static let kartForeground = adaptive(light: .black, dark: .white)
    static let kartInset = adaptive(light: .white, dark: .black)

    // In modalità chiara riprende il giallo del selettore piste in Timing.
    static let kartWarningText = adaptive(
        light: UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 1),
        dark: UIColor(Color.yellow)
    )
    // Testi delle penalità leggibili anche sull’intestazione gialla.
    static let kartPenaltyText = adaptive(
        light: UIColor(red: 0.22, green: 0.18, blue: 0.08, alpha: 1),
        dark: UIColor(Color.yellow)
    )
    static let kartNavigationTint = adaptive(
        light: UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 1),
        dark: UIColor(red: 1.0, green: 0.82, blue: 0.0, alpha: 1)
    )

    // Bordi dei messaggi più definiti sui pannelli chiari.
    static func kartMessageBorder(_ color: Color, opacity: Double) -> Color {
        let base = UIColor(color)
        return Color(uiColor: UIColor { traits in
            let resolved = base.resolvedColor(with: traits)
            guard traits.userInterfaceStyle != .dark else {
                return resolved.withAlphaComponent(CGFloat(opacity))
            }
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
                return resolved.withAlphaComponent(0.85)
            }
            return UIColor(red: red * 0.8, green: green * 0.8, blue: blue * 0.8, alpha: 0.85)
        })
    }

    static func kartBorder(opacity: Double) -> Color {
        adaptive(light: UIColor.black.withAlphaComponent(CGFloat(max(opacity, 0.18))),
                 dark: UIColor.white.withAlphaComponent(CGFloat(opacity)))
    }

    static func kartSecondaryText(opacity: Double) -> Color {
        adaptive(light: UIColor.black.withAlphaComponent(CGFloat(max(opacity, 0.65))),
                 dark: UIColor.white.withAlphaComponent(CGFloat(opacity)))
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
