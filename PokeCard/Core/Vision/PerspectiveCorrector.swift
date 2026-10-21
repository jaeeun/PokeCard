//
//  PerspectiveCorrector.swift
//  PokeCard
//
//  Dewarps a tilted card into a flat, front-facing image using Core Image's
//  CIPerspectiveCorrection filter, driven by the detected quad corners.
//

import Foundation
import CoreImage
import CoreGraphics

enum PerspectiveCorrector {

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Produces a front-facing, cropped image of the card.
    ///
    /// - Parameters:
    ///   - image: the full captured frame, in RAW sensor orientation.
    ///   - card: the detected quad in Vision-normalized coords (origin
    ///           bottom-left) measured on that same raw frame.
    /// - Returns: the dewarped card, rotated upright to portrait, or nil.
    static func correctedCard(from image: CGImage, card: DetectedCard) -> CGImage? {
        let ciImage = CIImage(cgImage: image)
        let w = ciImage.extent.width
        let h = ciImage.extent.height

        // Vision normalized (origin bottom-left) → CIImage pixel coords, whose
        // origin is also bottom-left, so only scaling is needed.
        func pt(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(pt(card.topLeft), forKey: "inputTopLeft")
        filter.setValue(pt(card.topRight), forKey: "inputTopRight")
        filter.setValue(pt(card.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(pt(card.bottomRight), forKey: "inputBottomRight")

        guard let output = filter.outputImage else { return nil }

        // The raw frame is landscape; a card held in portrait comes out rotated.
        // Rotate upright so the card reads top-to-bottom.
        let upright = output.oriented(.right)

        return context.createCGImage(upright, from: upright.extent)
    }
}
