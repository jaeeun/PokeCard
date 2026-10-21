//
//  Theme.swift
//  PokeCard
//
//  A small, "cute" design system: soft pastel palette, rounded shapes,
//  friendly typography, and reusable button/card styles. All colors are
//  original (no trademarked assets).
//

import SwiftUI

enum Theme {
    // MARK: - Palette (soft, candy-like pastels)
    static let primary      = Color(red: 1.00, green: 0.45, blue: 0.55)  // strawberry pink
    static let secondary    = Color(red: 0.45, green: 0.75, blue: 1.00)  // sky blue
    static let accent       = Color(red: 1.00, green: 0.82, blue: 0.35)  // soft yellow
    static let mint         = Color(red: 0.55, green: 0.90, blue: 0.75)  // mint green
    static let background    = Color(red: 1.00, green: 0.97, blue: 0.98)  // milk pink
    static let surface       = Color.white
    static let textPrimary   = Color(red: 0.25, green: 0.22, blue: 0.30)
    static let textSecondary = Color(red: 0.55, green: 0.52, blue: 0.60)

    static let cornerRadius: CGFloat = 22

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, secondary.opacity(0.18), mint.opacity(0.15)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [primary, primary.opacity(0.82)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Button style

struct CuteButtonStyle: ButtonStyle {
    var fill: AnyShapeStyle = AnyShapeStyle(Theme.primaryGradient)
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(.white.opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Theme.primary.opacity(0.25), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CuteButtonStyle {
    static var cute: CuteButtonStyle { CuteButtonStyle() }
    static func cute(fill: some ShapeStyle, foreground: Color = .white) -> CuteButtonStyle {
        CuteButtonStyle(fill: AnyShapeStyle(fill), foreground: foreground)
    }
}

// MARK: - Rounded text field

struct CuteTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.secondary.opacity(0.35), lineWidth: 1.5)
            )
    }
}

// MARK: - Soft card container

struct CuteCard<Content: View>: View {
    var tint: Color = Theme.primary
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .shadow(color: tint.opacity(0.18), radius: 14, x: 0, y: 8)
    }
}
