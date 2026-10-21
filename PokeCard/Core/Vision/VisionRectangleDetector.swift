//
//  VisionRectangleDetector.swift
//  PokeCard
//
//  On-device trading-card detection with Apple's Vision framework.
//
//  Two Vision requests run on each frame:
//   • VNDetectDocumentSegmentationRequest — ML segmentation that finds the
//     OUTER boundary of a flat object against the background (the whole card,
//     not the art window printed on it).
//   • VNDetectRectanglesRequest — classic edge-based quads, as a fallback.
//
//  Every quad must then pass card-specific gates measured in real pixel space:
//   1. Shape  — short/long side ≈ 63/88 mm (0.716), allowing for tilt.
//   2. Upright — the long side runs vertically on screen. A card's art window
//      is landscape, so this rejects it even when it's the only quad found.
//   3. Size   — must cover a meaningful part of the frame.
//  Finally, quads nested inside another candidate are discarded.
//
//  Frames arrive in raw sensor orientation (see CameraController). The raw
//  buffer is rotated 90° for portrait display, so the buffer's x-axis is the
//  screen's vertical axis.
//

import Foundation
import Vision
import CoreVideo

final class VisionRectangleDetector: CardRectangleDetecting, @unchecked Sendable {

    /// Physical trading-card ratio: 63 mm / 88 mm.
    private let targetAspect: CGFloat = 63.0 / 88.0
    /// Allowed deviation from `targetAspect` (covers perspective tilt).
    private let aspectTolerance: CGFloat = 0.09
    /// Ignore quads smaller than this fraction of the frame.
    private let minAreaFraction: CGFloat = 0.04

    /// Vision work runs here, never on the main thread.
    private let queue = DispatchQueue(label: "pokecard.vision.detect", qos: .userInitiated)

    func detectCandidates(in pixelBuffer: CVPixelBuffer) async -> [DetectedCard] {
        // The camera never mutates a delivered frame and Vision only reads it,
        // so handing the buffer to our queue is safe.
        nonisolated(unsafe) let buffer = pixelBuffer
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.runDetection(on: buffer))
            }
        }
    }

    private func runDetection(on pixelBuffer: CVPixelBuffer) -> [DetectedCard] {
        let size = CGSize(width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer))

        let documentRequest = VNDetectDocumentSegmentationRequest()

        let rectangleRequest = VNDetectRectanglesRequest()
        rectangleRequest.minimumAspectRatio = 0.5   // loose; precise gate below
        rectangleRequest.maximumAspectRatio = 0.9
        rectangleRequest.minimumSize = 0.15
        rectangleRequest.minimumConfidence = 0.4
        rectangleRequest.maximumObservations = 10
        rectangleRequest.quadratureTolerance = 20

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([documentRequest, rectangleRequest])
        } catch {
            return []
        }

        var candidates: [DetectedCard] = []
        for obs in documentRequest.results ?? [] {
            if let card = evaluate(obs, frameSize: size, isDocument: true) { candidates.append(card) }
        }
        for obs in rectangleRequest.results ?? [] {
            if let card = evaluate(obs, frameSize: size, isDocument: false) { candidates.append(card) }
        }
        return candidates.outermostCards()
    }

    /// Applies the card gates and scores a quad. Returns nil if it isn't card-like.
    private func evaluate(_ obs: VNRectangleObservation, frameSize size: CGSize, isDocument: Bool) -> DetectedCard? {
        // Normalized coords stretch x and y differently on a 4:3 buffer, so
        // measure in pixels to get the true physical ratio.
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        let tl = px(obs.topLeft), tr = px(obs.topRight)
        let bl = px(obs.bottomLeft), br = px(obs.bottomRight)

        // Average length of edges running along the buffer's x-axis vs y-axis.
        let xEdges = (hypot(tr.x - tl.x, tr.y - tl.y) + hypot(br.x - bl.x, br.y - bl.y)) / 2
        let yEdges = (hypot(bl.x - tl.x, bl.y - tl.y) + hypot(br.x - tr.x, br.y - tr.y)) / 2
        guard xEdges > 0, yEdges > 0 else { return nil }

        // 1. Shape gate.
        let aspect = min(xEdges, yEdges) / max(xEdges, yEdges)
        let aspectError = abs(aspect - targetAspect)
        guard aspectError <= aspectTolerance else { return nil }

        // 2. Upright gate: buffer x-axis = screen vertical, so the long edges
        //    must be the x-edges (card held upright in portrait, < 45° tilt).
        guard xEdges >= yEdges else { return nil }

        // 3. Size gate.
        let pixelArea = abs(
            (tl.x * tr.y - tr.x * tl.y) + (tr.x * br.y - br.x * tr.y) +
            (br.x * bl.y - bl.x * br.y) + (bl.x * tl.y - tl.x * bl.y)
        ) / 2
        let areaFraction = pixelArea / (size.width * size.height)
        guard areaFraction >= minAreaFraction else { return nil }

        var card = DetectedCard(
            topLeft: obs.topLeft,
            topRight: obs.topRight,
            bottomLeft: obs.bottomLeft,
            bottomRight: obs.bottomRight,
            confidence: obs.confidence
        )

        // Rank: big + centered + card-shaped. Segmentation quads get a small
        // bonus because they trace the card's outer edge.
        let center = card.centroid
        let centerScore = max(0, 1 - hypot(center.x - 0.5, center.y - 0.5) / 0.5)
        let aspectScore = 1 - aspectError / aspectTolerance
        card.score = Float(areaFraction) * 0.45
                   + Float(centerScore) * 0.25
                   + Float(aspectScore) * 0.20
                   + (isDocument ? 0.10 : 0)
        return card
    }
}
