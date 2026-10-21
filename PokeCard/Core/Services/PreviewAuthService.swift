//
//  PreviewAuthService.swift
//  PokeCard
//
//  In-memory auth service for SwiftUI previews and unit tests. No network,
//  no Firebase — just enough behavior to drive the UI.
//

import Foundation
import Combine

final class PreviewAuthService: AuthServicing {
    private let subject: CurrentValueSubject<AppUser?, Never>
    var userPublisher: AnyPublisher<AppUser?, Never> { subject.eraseToAnyPublisher() }
    var currentUser: AppUser? { subject.value }

    init(signedIn: Bool = false) {
        subject = CurrentValueSubject(signedIn ? Self.sample : nil)
    }

    static let sample = AppUser(
        id: "preview-uid",
        email: "ash@pallet.town",
        displayName: "Ash",
        photoURL: nil
    )

    func signIn(email: String, password: String) async throws -> AppUser {
        try await Task.sleep(nanoseconds: 300_000_000)
        let user = AppUser(id: "preview-uid", email: email, displayName: "Trainer")
        subject.send(user)
        return user
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AppUser {
        try await Task.sleep(nanoseconds: 300_000_000)
        let user = AppUser(id: "preview-uid", email: email, displayName: displayName ?? "Trainer")
        subject.send(user)
        return user
    }

    func signInWithGoogle() async throws -> AppUser {
        try await Task.sleep(nanoseconds: 300_000_000)
        subject.send(Self.sample)
        return Self.sample
    }

    func signOut() throws {
        subject.send(nil)
    }
}
