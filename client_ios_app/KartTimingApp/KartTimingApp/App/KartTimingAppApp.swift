//
//  KartTimingAppApp.swift
//  KartTimingApp
//
//  Created by Marco Caruso on 26/06/2026.
//

import SwiftUI
import UIKit

// MARK: - AppDelegate (gestione orientamento)
class AppDelegate: NSObject, UIApplicationDelegate {
    /// Imposta il valore qui per bloccare l'orientamento globalmente.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}

@main
struct KartTimingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authState    = AuthState.shared
    @StateObject private var appEnv       = AppEnvironment.shared
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        KeyboardDismissManager.shared.setupGlobalTapToDismissKeyboard()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authState.isLoggedIn {
                    HomeView()
                        .environmentObject(authState)
                        .environmentObject(appEnv)
                } else {
                    LoginView()
                        .environmentObject(authState)
                        .environmentObject(appEnv)
                }
            }
            .preferredColorScheme(theme.colorScheme)
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

