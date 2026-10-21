//
//  CameraPreview.swift
//  PokeCard
//
//  SwiftUI host for the camera's AVCaptureVideoPreviewLayer.
//
//  The layer is owned by CameraController and kept exactly the size of this
//  view, so points produced by `layerPointConverted(...)` are directly in this
//  view's (and the overlay's) local coordinate space.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewView {
        PreviewView(previewLayer: previewLayer)
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        private let previewLayer: AVCaptureVideoPreviewLayer

        init(previewLayer: AVCaptureVideoPreviewLayer) {
            self.previewLayer = previewLayer
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(previewLayer)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            // Keep the layer pinned to the view without implicit animations.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = bounds
            CATransaction.commit()
        }
    }
}

extension AVCaptureVideoPreviewLayer {
    /// Converts a quad from Vision's normalized space (origin bottom-left,
    /// y-up, measured on the RAW sensor-oriented buffer) into this layer's
    /// point space. The layer applies its own rotation and aspect-fill crop,
    /// so the result matches exactly what is on screen.
    ///
    /// - Parameter corners: `[topLeft, topRight, bottomRight, bottomLeft]`.
    func layerPoints(forVisionCorners corners: [CGPoint]) -> [CGPoint] {
        corners.map { pt in
            // Vision (bottom-left origin) → capture-device space (top-left).
            layerPointConverted(fromCaptureDevicePoint: CGPoint(x: pt.x, y: 1 - pt.y))
        }
    }
}
