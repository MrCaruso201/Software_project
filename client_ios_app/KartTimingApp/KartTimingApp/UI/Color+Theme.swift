import SwiftUI

extension Color {
    static let kartBG      = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let kartPanel   = Color(red: 0.10, green: 0.10, blue: 0.13)
    static let kartAccent  = Color(red: 0.96, green: 0.14, blue: 0.21)   // rosso
    static let kartGreen   = Color(red: 0.13, green: 0.76, blue: 0.37)
    static let kartRed     = Color(red: 0.93, green: 0.27, blue: 0.27)
    static let kartDim     = Color.white.opacity(0.35)
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
