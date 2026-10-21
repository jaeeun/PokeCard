//
//  AppBootstrap.swift
//  PokeCard
//
//  Centralizes third-party SDK initialization so the view layer stays clean.
//

import Foundation

#if canImport(FirebaseCore)
import FirebaseCore
#endif

enum AppBootstrap {
    /// Configures third-party services at launch.
    ///
    /// Firebase is only configured when the `GoogleService-Info.plist` file is
    /// present in the bundle. This lets the project build and run (e.g. for UI
    /// previews) before Firebase credentials are added, and avoids a hard crash.
    static func configure() {
        #if canImport(FirebaseCore)
        guard Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else {
            print("[AppBootstrap] GoogleService-Info.plist not found — skipping Firebase configuration. " +
                  "Add it to enable authentication.")
            return
        }
        FirebaseApp.configure()
        print("[AppBootstrap] Firebase configured.")
        #else
        print("[AppBootstrap] FirebaseCore not linked — running without Firebase.")
        #endif
    }
}
