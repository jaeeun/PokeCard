//
//  RootView.swift
//  PokeCard
//
//  Decides whether to show the authentication flow or the main app flow.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isSignedIn {
                NavigationStack(path: $appState.path) {
                    HomeView()
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .home:
                                HomeView()
                            case .scanner:
                                ScannerView()
                            case .collection:
                                CollectionView()
                            }
                        }
                }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: appState.isSignedIn)
        .onAppear { appState.restoreSession() }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState(authService: PreviewAuthService(signedIn: true)))
}
