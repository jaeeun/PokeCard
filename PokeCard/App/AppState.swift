//
//  AppState.swift
//  PokeCard
//
//  Global observable app state. Holds the authentication session and the
//  current top-level route. Views observe this to decide what to render.
//

import Foundation
import Combine

/// Top-level navigation destinations reachable from the authenticated home.
enum AppRoute: Hashable {
    case home
    case scanner
    case collection
}

@MainActor
final class AppState: ObservableObject {
    /// The currently signed-in user, or `nil` when signed out.
    @Published var currentUser: AppUser?

    /// Whether an auth check / sign-in operation is in flight.
    @Published var isAuthenticating: Bool = false

    /// True when the user chose to skip sign-in and use the app locally.
    @Published var isGuest: Bool = false

    /// Navigation path for the authenticated flow.
    @Published var path: [AppRoute] = []

    private let authService: AuthServicing
    private var cancellables = Set<AnyCancellable>()

    var isSignedIn: Bool { currentUser != nil }

    init(authService: AuthServicing = AuthServiceFactory.make()) {
        self.authService = authService
        bind()
    }

    private func bind() {
        authService.userPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.currentUser = user
            }
            .store(in: &cancellables)
    }

    // MARK: - Auth intents

    func signIn(email: String, password: String) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        currentUser = try await authService.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String, displayName: String?) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        currentUser = try await authService.signUp(email: email, password: password, displayName: displayName)
    }

    func signInWithGoogle() async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        currentUser = try await authService.signInWithGoogle()
    }

    /// Skip authentication and use the app as a local-only guest. Useful when
    /// Firebase isn't configured, or for users who just want to scan without
    /// an account. Guest sessions are not persisted across launches.
    func continueAsGuest() {
        isGuest = true
        currentUser = AppUser(id: "guest", displayName: "Guest")
    }

    func signOut() {
        try? authService.signOut()
        isGuest = false
        currentUser = nil
        path.removeAll()
    }

    func restoreSession() {
        // Don't override an active guest session with the (empty) auth session.
        guard !isGuest else { return }
        currentUser = authService.currentUser
    }
}
