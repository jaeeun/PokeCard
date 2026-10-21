//
//  CardGuideOverlay.swift
//  PokeCard
//
//  Draws animated, rounded corner "guiding lines" around a detected card.
//  When a card is detected, the four corners snap to its quad with a springy
//  animation and glow in the theme color; otherwise a dashed hint frame shows
//  where to aim.
//

import SwiftUI

struct CardGuideOverlay: View {
    /// Detected card corners already converted to VIEW coordinates (points),
    /// in order: topLeft, topRight, bottomRight, bottomLeft. Nil when none.
    let viewCorners: [CGPoint]?
    /// Whether the detected card passed OCR validation (turns the guide green).
    let isValidated: Bool

    private var tint: Color { isValidated ? Theme.mint : Theme.primary }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let corners = viewCorners, corners.count == 4 {
                    // Rounded guide hugging the detected quad.
                    CornerBrackets(corners: corners, tint: tint)
                        .transition(.opacity)
                } else {
                    // Idle hint frame centered in view.
                    hintFrame(in: geo.size)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewCorners)
            .animation(.easeInOut, value: isValidated)
        }
        .allowsHitTesting(false)
    }

    private func hintFrame(in size: CGSize) -> some View {
        let w = size.width * 0.7
        let h = w / 0.716           // card aspect
        return RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(style: StrokeStyle(lineWidth: 3, dash: [12, 10]))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: w, height: min(h, size.height * 0.8))
            .position(x: size.width / 2, y: size.height / 2)
    }
}

/// Draws four rounded L-shaped brackets at the detected card's corners, plus
/// a translucent connecting outline.
private struct CornerBrackets: View {
    let corners: [CGPoint]   // TL, TR, BR, BL
    let tint: Color

    var body: some View {
        ZStack {
            // Soft connecting outline.
            QuadShape(points: corners)
                .stroke(tint.opacity(0.5), lineWidth: 2)
                .background(QuadShape(points: corners).fill(tint.opacity(0.08)))

            // Rounded corner brackets.
            ForEach(0..<4, id: \.self) { i in
                let p = corners[i]
                let neighbors = bracketNeighbors(index: i)
                CornerBracket(
                    corner: p,
                    toA: corners[neighbors.0],
                    toB: corners[neighbors.1],
                    tint: tint
                )
            }
        }
        .shadow(color: tint.opacity(0.5), radius: 6)
    }

    // For each corner, the two adjacent corners that define the bracket arms.
    private func bracketNeighbors(index: Int) -> (Int, Int) {
        switch index {
        case 0: return (1, 3) // TL → TR, BL
        case 1: return (0, 2) // TR → TL, BR
        case 2: return (1, 3) // BR → TR, BL
        default: return (2, 0) // BL → BR, TL
        }
    }
}

/// A single rounded corner bracket: two short arms meeting at `corner`.
private struct CornerBracket: View {
    let corner: CGPoint
    let toA: CGPoint
    let toB: CGPoint
    let tint: Color

    private let armLength: CGFloat = 26

    var body: some View {
        Path { path in
            let a = pointAlong(from: corner, to: toA, distance: armLength)
            let b = pointAlong(from: corner, to: toB, distance: armLength)
            path.move(to: a)
            path.addQuadCurve(to: b, control: corner)
        }
        .stroke(style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        .foregroundStyle(tint)
    }

    private func pointAlong(from: CGPoint, to: CGPoint, distance: CGFloat) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = max(hypot(dx, dy), 0.0001)
        let t = min(distance / len, 1)
        return CGPoint(x: from.x + dx * t, y: from.y + dy * t)
    }
}

/// Fills/strokes a quadrilateral from four points.
private struct QuadShape: Shape {
    let points: [CGPoint]  // TL, TR, BR, BL
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count == 4 else { return path }
        path.move(to: points[0])
        path.addLine(to: points[1])
        path.addLine(to: points[2])
        path.addLine(to: points[3])
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.black
        CardGuideOverlay(
            viewCorners: [
                CGPoint(x: 90, y: 180),
                CGPoint(x: 300, y: 170),
                CGPoint(x: 305, y: 470),
                CGPoint(x: 85, y: 480)
            ],
            isValidated: false
        )
    }
    .ignoresSafeArea()
}
