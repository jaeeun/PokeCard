//
//  CardTracker.swift
//  PokeCard
//
//  Turns noisy per-frame candidates into ONE stable card on screen.
//
//   • Searching: a candidate must stay the best for `confirmFrames`
//     consecutive frames before it's shown, so one-frame flashes never appear.
//   • Locked: only the candidate matching the tracked card is followed. Every
//     other rectangle in the scene is ignored — the guide no longer hops
//     between quads.
//   • Smoothing: the displayed quad eases toward each new match.
//   • Hysteresis: a few missed frames don't drop the lock.
//
//  Pure value logic with no dependencies, so it is easy to unit test.
//

import Foundation
import CoreGraphics

struct CardTracker {

    /// 0...1. Higher follows faster, lower is smoother.
    var smoothing: CGFloat = 0.35
    /// Max mean corner distance (normalized) for two quads to be the same card.
    var associationThreshold: CGFloat = 0.12
    /// Consecutive consistent frames needed before a new card is shown.
    var confirmFrames = 3
    /// Consecutive frames without a match before the lock is released.
    var maxMissedFrames = 6

    private var current: DetectedCard?
    private var missedFrames = 0
    private var pending: DetectedCard?
    private var pendingCount = 0

    /// Feed this frame's candidates (best first). Returns the card to display.
    mutating func update(with candidates: [DetectedCard]) -> DetectedCard? {
        if let tracked = current {
            return follow(tracked, candidates: candidates)
        }
        return acquire(candidates)
    }

    mutating func reset() {
        current = nil
        missedFrames = 0
        pending = nil
        pendingCount = 0
    }

    // MARK: - Locked

    private mutating func follow(_ tracked: DetectedCard, candidates: [DetectedCard]) -> DetectedCard? {
        let match = candidates.min { tracked.cornerDistance(to: $0) < tracked.cornerDistance(to: $1) }
        if let match, tracked.cornerDistance(to: match) <= associationThreshold {
            missedFrames = 0
            let smoothed = tracked.lerp(to: match, t: smoothing)
            current = smoothed
            return smoothed
        }
        // No candidate matches the tracked card: hold it briefly, then let go.
        missedFrames += 1
        if missedFrames > maxMissedFrames {
            reset()
        }
        return current
    }

    // MARK: - Searching

    private mutating func acquire(_ candidates: [DetectedCard]) -> DetectedCard? {
        guard let best = candidates.first else {
            pending = nil
            pendingCount = 0
            return nil
        }
        if let previous = pending, previous.cornerDistance(to: best) <= associationThreshold {
            pendingCount += 1
            pending = previous.lerp(to: best, t: 0.5)
        } else {
            pending = best
            pendingCount = 1
        }
        guard pendingCount >= confirmFrames, let confirmed = pending else { return nil }
        current = confirmed
        missedFrames = 0
        pending = nil
        pendingCount = 0
        return confirmed
    }
}
