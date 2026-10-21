//
//  PokeCardApp.swift
//  PokeCard
//
//  App entry point. Wires up global app state and routes between the
//  authentication flow and the main app flow.
//
//  ⚠️ LICENSING / COPYRIGHT NOTICE
//  This is an UNOFFICIAL, fan-made utility. It is NOT affiliated with,
//  endorsed by, or sponsored by The Pokémon Company, Nintendo, Game Freak,
//  or Creatures Inc. The app does NOT bundle, reproduce, or redistribute any
//  official Pokémon artwork or trademarked assets. It only processes photos
//  that the user captures themselves, on-device, and derives *factual* data
//  (card name, set number) via OCR. See LICENSING.md for the full policy.
//

import SwiftUI
import SwiftData

@main
struct PokeCardApp: App {
    // Global, observable application state (auth session, routing).
    @StateObject private var appState: AppState

    init() {
        // IMPORTANT: Firebase must be configured BEFORE anything touches
        // `Auth.auth()`. A default-initialized `@StateObject` would be
        // evaluated before this initializer body, so we configure Firebase
        // first and then build AppState explicitly to guarantee ordering.
        AppBootstrap.configure()
        _appState = StateObject(wrappedValue: AppState())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        .modelContainer(for: CollectedCard.self)
    }
}
