//
//  CardRectangleDetecting.swift
//  PokeCard
//
//  Abstraction over "find card-shaped quads in a frame".
//
//  The default implementation uses Apple's Vision framework, which runs fully
//  ON-DEVICE and ships with iOS — no third-party models, no trademarked
//  training data, no licensing concerns.
//
//  IMPORTANT (licensing): if you ever plug in a custom CoreML/YOLO detector,
//  train it on the generic *shape of a trading card*, NOT on Pokémon artwork.
//  Do not use copyrighted card images as training data.
//

import Foundation
import CoreGraphics
import CoreVideo

/// A detected card-like quadrilateral, in Vision's normalized coordinate space
/// (origin bottom-left, 0...1 on both axes) of the RAW camera buffer.
struct DetectedCard: Equatable {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
    /// Detector confidence 0...1.
    let confidence: Float
    /// Ranking score assigned by the detector (higher = better candidate).
    var score: Float = 0

    var normalizedCorners: [CGPoint] { [topLeft, topRight, bottomRight, bottomLeft] }

    var centroid: CGPoint {
        let c = normalizedCorners
        return CGPoint(x: c.map(\.x).reduce(0, +) / 4, y: c.map(\.y).reduce(0, +) / 4)
    }

    /// Shoelace area in normalized units (only used for relative comparison).
    var normalizedArea: CGFloat {
        let c = normalizedCorners
        var sum: CGFloat = 0
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            sum += a.x * b.y - b.x * a.y
        }
        return abs(sum) / 2
    }

    /// True if every corner of `other` lies inside this (convex) quad.
    func contains(_ other: DetectedCard) -> Bool {
        other.normalizedCorners.allSatisfy(contains(point:))
    }

    func contains(point p: CGPoint) -> Bool {
        let c = normalizedCorners
        var sign: CGFloat = 0
        for i in 0..<4 {
            let a = c[i], b = c[(i + 1) % 4]
            let cross = (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
            if cross == 0 { continue }
            if sign == 0 { sign = cross > 0 ? 1 : -1 }
            else if (cross > 0 ? 1 : -1) != sign { return false }
        }
        return true
    }

    /// Per-corner linear interpolation. `t` = 0 keeps `self`, 1 jumps to `other`.
    func lerp(to other: DetectedCard, t: CGFloat) -> DetectedCard {
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return DetectedCard(
            topLeft: mix(topLeft, other.topLeft),
            topRight: mix(topRight, other.topRight),
            bottomLeft: mix(bottomLeft, other.bottomLeft),
            bottomRight: mix(bottomRight, other.bottomRight),
            confidence: confidence + (other.confidence - confidence) * Float(t),
            score: other.score
        )
    }

    /// Mean distance between corresponding corners (normalized units).
    func cornerDistance(to other: DetectedCard) -> CGFloat {
        let a = normalizedCorners, b = other.normalizedCorners
        var sum: CGFloat = 0
        for i in 0..<4 { sum += hypot(a[i].x - b[i].x, a[i].y - b[i].y) }
        return sum / 4
    }
}

extension Array where Element == DetectedCard {
    /// Drops duplicates and any quad nested inside a larger one (e.g. the art
    /// window inside a card), then sorts best score first.
    func outermostCards(duplicateThreshold: CGFloat = 0.03) -> [DetectedCard] {
        var kept: [DetectedCard] = []
        for candidate in sorted(by: { $0.normalizedArea > $1.normalizedArea }) {
            let isDuplicate = kept.contains { $0.cornerDistance(to: candidate) < duplicateThreshold }
            let isNested = kept.contains { $0.contains(candidate) }
            if !isDuplicate && !isNested { kept.append(candidate) }
        }
        return kept.sorted { $0.score > $1.score }
    }
}

protocol CardRectangleDetecting: AnyObject {
    /// Card-like quads found in the frame, best first. Empty when none.
    func detectCandidates(in pixelBuffer: CVPixelBuffer) async -> [DetectedCard]
}
