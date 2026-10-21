//
//  AuthServicing.swift
//  PokeCard
//
//  Abstraction over the authentication backend. The app depends only on this
//  protocol, so Firebase can be swapped for mocks (previews/tests) or another
//  provider without touching the UI.
//

import Foundation
import Combine

enum AuthError: LocalizedError {
    case notConfigured
    case cancelled
    case invalidCredentials
    case missingClientID
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Authentication is not configured. Add GoogleService-Info.plist and enable Firebase Auth."
        case .cancelled:
            return "Sign-in was cancelled."
        case .invalidCredentials:
            return "The email or password is incorrect."
        case .missingClientID:
            return "Missing Google client ID. Check your Firebase configuration."
        case .underlying(let message):
            return message
        }
    }
}

protocol AuthServicing {
    /// Emits the current user whenever the auth state changes.
    var userPublisher: AnyPublisher<AppUser?, Never> { get }

    /// The currently cached user, if any.
    var currentUser: AppUser? { get }

    func signIn(email: String, password: String) async throws -> AppUser
    func signUp(email: String, password: String, displayName: String?) async throws -> AppUser
    func signInWithGoogle() async throws -> AppUser
    func signOut() throws
}
