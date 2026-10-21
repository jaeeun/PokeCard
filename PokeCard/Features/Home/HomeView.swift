//
//  HomeView.swift
//  PokeCard
//
//  Authenticated landing screen. Two big, cute entry points: Scan a card,
//  or browse the collection.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 28) {
                greeting

                VStack(spacing: 20) {
                    EntryCard(
                        title: "Scan a Card",
                        subtitle: "Point your camera at a card",
                        systemImage: "camera.viewfinder",
                        tint: Theme.primary
                    ) {
                        appState.path.append(.scanner)
                    }

                    EntryCard(
                        title: "My Collection",
                        subtitle: "Browse your saved cards",
                        systemImage: "square.stack.3d.up.fill",
                        tint: Theme.secondary
                    ) {
                        appState.path.append(.collection)
                    }
                }

                Spacer()

                disclaimer
            }
            .padding(24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        appState.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "arrow.right.square")
                    }
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.primary)
                }
            }
        }
    }

    private var greeting: some View {
        VStack(spacing: 10) {
            MascotBadge(size: 84)
            Text("Hi, \(appState.currentUser?.displayName ?? "Trainer")! 👋")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("What would you like to do today?")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private var disclaimer: some View {
        Text("Unofficial fan app. Not affiliated with The Pokémon Company. " +
             "Only your own photos are processed, on-device.")
            .font(.caption2)
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textSecondary.opacity(0.8))
            .padding(.horizontal, 12)
    }
}

/// A large, tappable, cute card used as a home entry point.
private struct EntryCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 64, height: 64)
                    Image(systemName: systemImage)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .foregroundStyle(tint.opacity(0.6))
            }
            .padding(22)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: tint.opacity(0.2), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        HomeView()
            .environmentObject(AppState(authService: PreviewAuthService(signedIn: true)))
    }
}
