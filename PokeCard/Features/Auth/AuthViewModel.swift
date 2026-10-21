//
//  AuthViewModel.swift
//  PokeCard
//
//  Drives the login & sign-up screens. Validates input and relays intents
//  to AppState, surfacing errors for display.
//

import Foundation

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var displayName = ""

    @Published var errorMessage: String?
    @Published var isBusy = false

    private var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Re-point this view model at the environment-provided AppState. Needed
    /// because SwiftUI's @StateObject must be initialized before the
    /// environment is available.
    func rebind(to appState: AppState) {
        self.appState = appState
    }

    var isEmailValid: Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }

    var isPasswordValid: Bool {
        password.count >= 6
    }

    var canSignIn: Bool { isEmailValid && isPasswordValid && !isBusy }
    var canSignUp: Bool { canSignIn && password == confirmPassword }

    func signIn() async {
        guard canSignIn else {
            errorMessage = "Enter a valid email and a password of at least 6 characters."
            return
        }
        await run { try await self.appState.signIn(email: self.email, password: self.password) }
    }

    func signUp() async {
        guard canSignUp else {
            errorMessage = password == confirmPassword
                ? "Enter a valid email and a password of at least 6 characters."
                : "Passwords do not match."
            return
        }
        let name = displayName.trimmingCharacters(in: .whitespaces)
        await run {
            try await self.appState.signUp(
                email: self.email,
                password: self.password,
                displayName: name.isEmpty ? nil : name
            )
        }
    }

    func signInWithGoogle() async {
        await run { try await self.appState.signInWithGoogle() }
    }

    private func run(_ operation: @escaping () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
