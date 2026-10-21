//
//  FirebaseAuthService.swift
//  PokeCard
//
//  Firebase-backed implementation of AuthServicing.
//
//  Dependencies (add via Swift Package Manager — see README):
//    • firebase-ios-sdk  → FirebaseAuth
//    • GoogleSignIn-iOS   → GoogleSignIn
//
//  The whole file is guarded by `canImport` so the project still compiles
//  before those packages are added (e.g. while prototyping the UI).
//

import Foundation
import Combine

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(UIKit)
import UIKit
#endif

final class FirebaseAuthService: AuthServicing {

    private let subject = CurrentValueSubject<AppUser?, Never>(nil)
    var userPublisher: AnyPublisher<AppUser?, Never> { subject.eraseToAnyPublisher() }
    var currentUser: AppUser? { subject.value }

    #if canImport(FirebaseAuth)
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        // Only touch `Auth.auth()` if Firebase has actually been configured.
        // Accessing it before `FirebaseApp.configure()` triggers a fatalError,
        // so we guard against that and simply stay in a signed-out state.
        guard FirebaseApp.app() != nil else {
            print("[FirebaseAuthService] Firebase not configured — auth disabled. " +
                  "Add GoogleService-Info.plist and ensure FirebaseApp.configure() runs at launch.")
            return
        }
        // Keep local state in sync with Firebase's auth session.
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.subject.send(user.map(Self.mapUser))
        }
        subject.send(Auth.auth().currentUser.map(Self.mapUser))
    }

    deinit {
        if let handle { Auth.auth().removeStateDidChangeListener(handle) }
    }

    /// True when Firebase has been configured and auth can be used.
    private var isConfigured: Bool { FirebaseApp.app() != nil }

    private static func mapUser(_ user: User) -> AppUser {
        AppUser(
            id: user.uid,
            email: user.email,
            displayName: user.displayName,
            photoURL: user.photoURL
        )
    }

    // MARK: - Email / password

    func signIn(email: String, password: String) async throws -> AppUser {
        guard isConfigured else { throw AuthError.notConfigured }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            return Self.mapUser(result.user)
        } catch {
            throw AuthError.underlying(error.localizedDescription)
        }
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> AppUser {
        guard isConfigured else { throw AuthError.notConfigured }
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            if let displayName, !displayName.isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = displayName
                try await change.commitChanges()
            }
            return Self.mapUser(result.user)
        } catch {
            throw AuthError.underlying(error.localizedDescription)
        }
    }

    // MARK: - Google

    @MainActor
    func signInWithGoogle() async throws -> AppUser {
        #if canImport(GoogleSignIn) && canImport(FirebaseCore) && canImport(UIKit)
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let presenting = Self.topViewController() else {
            throw AuthError.underlying("No presenting view controller available for Google Sign-In.")
        }

        let gidResult: GIDSignInResult
        do {
            gidResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
        } catch {
            // GIDSignIn surfaces user cancellation as an error.
            throw AuthError.cancelled
        }

        guard let idToken = gidResult.user.idToken?.tokenString else {
            throw AuthError.invalidCredentials
        }
        let accessToken = gidResult.user.accessToken.tokenString

        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        do {
            let authResult = try await Auth.auth().signIn(with: credential)
            return Self.mapUser(authResult.user)
        } catch {
            throw AuthError.underlying(error.localizedDescription)
        }
        #else
        throw AuthError.notConfigured
        #endif
    }

    func signOut() throws {
        guard isConfigured else { subject.send(nil); return }
        try Auth.auth().signOut()
        #if canImport(GoogleSignIn)
        GIDSignIn.sharedInstance.signOut()
        #endif
        subject.send(nil)
    }

    #if canImport(UIKit)
    /// Finds the top-most view controller to present Google's sign-in sheet.
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
    #endif

    #else
    // Firebase not linked yet: provide a clear runtime signal.
    init() {}

    func signIn(email: String, password: String) async throws -> AppUser {
        throw AuthError.notConfigured
    }
    func signUp(email: String, password: String, displayName: String?) async throws -> AppUser {
        throw AuthError.notConfigured
    }
    func signInWithGoogle() async throws -> AppUser {
        throw AuthError.notConfigured
    }
    func signOut() throws {
        subject.send(nil)
    }
    #endif
}

#if canImport(UIKit)
private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}
#endif
