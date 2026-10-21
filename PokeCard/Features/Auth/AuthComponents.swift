//
//  AuthComponents.swift
//  PokeCard
//
//  Shared, original UI pieces for the auth screens. The mascot is a simple
//  original "poké-ball-ish" shape drawn with SF Symbols + shapes — NOT the
//  trademarked Poké Ball design. Keep it generic and original.
//

import SwiftUI

/// A friendly, original mascot badge (two-tone rounded circle). Purely
/// decorative and original — no trademarked logos.
struct MascotBadge: View {
    var size: CGFloat = 96

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.primaryGradient)
                .frame(width: size, height: size)
            Circle()
                .fill(.white)
                .frame(width: size * 0.34, height: size * 0.34)
            Circle()
                .stroke(Theme.textPrimary.opacity(0.15), lineWidth: 2)
                .frame(width: size, height: size)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundStyle(Theme.accent)
                .offset(x: size * 0.26, y: -size * 0.28)
        }
        .shadow(color: Theme.primary.opacity(0.3), radius: 12, x: 0, y: 8)
        .accessibilityHidden(true)
    }
}

/// Google sign-in button that matches the cute theme while remaining clearly
/// recognizable. (Add the "G" asset per Google branding guidelines if desired.)
struct GoogleSignInButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "g.circle.fill")
                    .font(.title3)
                Text("Continue with Google")
                    .font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Theme.textPrimary)
            .background(.white, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.textSecondary.opacity(0.25), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// An "or" divider used between email and social sign-in.
struct OrDivider: View {
    var body: some View {
        HStack {
            line
            Text("or")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            line
        }
    }
    private var line: some View {
        Rectangle()
            .fill(Theme.textSecondary.opacity(0.2))
            .frame(height: 1)
    }
}
