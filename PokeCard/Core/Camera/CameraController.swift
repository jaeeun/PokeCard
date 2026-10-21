//
//  CameraController.swift
//  PokeCard
//
//  Wraps an AVCaptureSession: live preview + per-frame pixel buffers for
//  on-device rectangle detection, plus still-photo capture for OCR.
//
//  PRIVACY: frames never leave the device. All processing is local.
//
//  Threading: the capture session is configured and driven on a private
//  serial queue. Published UI state is always delivered on the main queue.
//

import Foundation
import AVFoundation
import CoreVideo
import Combine

/// `@unchecked Sendable`: all mutable capture-session state is confined to the
/// private `sessionQueue`, and `@Published` UI state is updated on the main
/// actor. The compiler can't verify this invariant, so we assert it manually.
final class CameraController: NSObject, ObservableObject, @unchecked Sendable {

    enum AuthorizationState {
        case unknown, authorized, denied
    }

    @Published private(set) var authorization: AuthorizationState = .unknown

    let session = AVCaptureSession()

    /// Latest video frame for detection. Delivered off the main thread.
    let frames = PassthroughSubject<CVPixelBuffer, Never>()

    /// The single preview layer for this session. Owned here (not by a SwiftUI
    /// view) so the scanner can always convert Vision coordinates through it.
    let previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    override init() {
        super.init()
        previewLayer.session = session
    }

    private let sessionQueue = DispatchQueue(label: "pokecard.camera.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<CGImage?, Never>?
    private var isConfigured = false

    // MARK: - Permissions

    func requestAccess() async {
        let state: AuthorizationState
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            state = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            state = granted ? .authorized : .denied
        default:
            state = .denied
        }
        await MainActor.run { self.authorization = state }
    }

    /// Snapshot of the current authorization (safe to read synchronously).
    var currentAuthorization: AuthorizationState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .unknown
        default: return .denied
        }
    }

    // MARK: - Lifecycle

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
            self.configureIfNeeded()
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }

        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "pokecard.camera.frames"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // COORDINATE SYSTEM CONTRACT
        // Video frames and photos stay in the camera sensor's native
        // orientation (rotation 0). Vision runs on these raw buffers, so its
        // results are in "capture device" space — exactly what
        // AVCaptureVideoPreviewLayer.layerPointConverted(fromCaptureDevicePoint:)
        // expects. The preview layer alone handles rotation + aspect-fill crop
        // when converting to screen points, so the overlay always matches what
        // is actually displayed.
        for output in [videoOutput as AVCaptureOutput, photoOutput as AVCaptureOutput] {
            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(0) {
                connection.videoRotationAngle = 0
            }
        }

        session.commitConfiguration()

        // Display the preview upright in portrait.
        DispatchQueue.main.async { [weak self] in
            if let connection = self?.previewLayer.connection,
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }

    // MARK: - Still capture (for OCR)

    func capturePhoto() async -> CGImage? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
}

// MARK: - Frame delegate

extension CameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frames.send(buffer)
    }
}

// MARK: - Photo delegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let cgImage = photo.cgImageRepresentation()
        let continuation = photoContinuation
        photoContinuation = nil
        continuation?.resume(returning: cgImage)
    }
}
