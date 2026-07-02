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
    }
}

