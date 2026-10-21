//
//  AuthServiceFactory.swift
//  PokeCard
//
//  Selects the concrete auth service. Uses the preview/mock service when
//  running inside SwiftUI previews, Firebase otherwise.
//

import Foundation

enum AuthServiceFactory {
    static func make() -> AuthServicing {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return PreviewAuthService()
        }
        #endif
        return FirebaseAuthService()
    }
}
