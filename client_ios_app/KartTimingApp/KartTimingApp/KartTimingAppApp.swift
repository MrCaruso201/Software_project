//
//  KartTimingAppApp.swift
//  KartTimingApp
//
//  Created by Marco Caruso on 26/06/2026.
//

import SwiftUI

@main
struct KartTimingApp: App {
    @StateObject private var authState = AuthState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            if authState.isLoggedIn {
                WelcomeView()
                    .environmentObject(authState)
            } else {
                LoginView()
                    .environmentObject(authState)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Quando l'app va in background/termina con una sessione guest,
            // esegui subito il logout così i token "viewer" non rimangono nel Keychain.
            if newPhase == .background && authState.isGuestSession {
                authState.logout()
            }
        }
    }
}

