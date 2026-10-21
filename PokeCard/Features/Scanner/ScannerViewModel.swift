//
//  ScannerViewModel.swift
//  PokeCard
//
//  Orchestrates: camera frames → rectangle detection → corner conversion →
//  (on user capture) OCR → Pokémon-card validation.
//

import Foundation
import Combine
import CoreGraphics
import CoreVideo
import Vision
import SwiftData
import CoreImage

@MainActor
final class ScannerViewModel: ObservableObject {

    enum Phase: Equatable {
        case searching          // looking for a card-shaped rectangle
        case locked             // a card is tracked; checking auto-capture conditions
        case analyzing          // auto-captured; OCR + validation in progress
        case result(CardValidation)
    }

    @Published var phase: Phase = .searching
    /// Latest detection in Vision-normalized coords (origin bottom-left).
    @Published var detectedCard: DetectedCard?
    @Published var permissionDenied = false

    /// Auto-capture gating signals, surfaced for the UI.
    /// True when the tracked card's center has stopped moving.
    @Published var isPositionStable = false
    /// The set number currently read from the live frame (e.g. "001/081C"),
    /// nil until a valid one is seen.
    @Published var liveSetNumber: String?

    /// The perspective-corrected, front-facing card image, shown centered
    /// once an auto-capture succeeds.
    @Published private(set) var correctedCard: CGImage?

    /// The cropped image kept for saving to the collection.
    private(set) var lastCapturedImage: CGImage?

    /// The language the latest result was read in (for display + re-read UI).
    @Published private(set) var recognizedLanguage: OCRLanguage?
    /// True while a user-requested re-read in another language is running.
    @Published private(set) var isRereading = false

    /// The language the user chose to scan in. `nil` until they pick one, which
    /// is when scanning (camera + detection) actually begins.
    @Published var selectedLanguage: OCRLanguage?

    let camera = CameraController()

    private let detector: CardRectangleDetecting
    private let recognizer = CardTextRecognizer()
    private let validator = PokemonCardValidator()
    private let priceEstimator: PriceEstimating

    private var cancellables = Set<AnyCancellable>()
    private var isDetecting = false
    private var tracker = CardTracker()
    private var isCapturing = false

    // MARK: Auto-capture condition state

    /// Max per-frame center movement (normalized units) to count as "stable".
    private let centerStabilityThreshold: CGFloat = 0.012
    /// Consecutive stable frames required before position is considered settled.
    private let stableFramesRequired = 4
    private var lastCenter: CGPoint?
    private var stableFrameCount = 0
    /// Whether a live, valid set number has been confirmed for the tracked card.
    private var hasValidSetNumber = false
    /// Serializes the lightweight live OCR so we don't stack requests.
    private var isReadingLive = false

    init(
        detector: CardRectangleDetecting = VisionRectangleDetector(),
        priceEstimator: PriceEstimating = PriceEstimatorFactory.make()
    ) {
        self.detector = detector
        self.priceEstimator = priceEstimator
    }

    func onAppear() async {
        await camera.requestAccess()
        guard camera.authorization == .authorized else {
            permissionDenied = true
            return
        }
        // Start the live preview immediately so the user sees the camera while
        // choosing a language, but don't run detection/OCR until they pick one.
        camera.start()
        if selectedLanguage != nil {
            bindFrames()
        }
    }

    /// Called when the user picks a scan language. Begins detection + OCR.
    func startScanning(language: OCRLanguage) {
        reset()
        selectedLanguage = language
        if cancellables.isEmpty {
            bindFrames()
        }
    }

    /// Lets the user go back and pick a different scan language.
    func changeLanguage() {
        cancellables.removeAll()
        selectedLanguage = nil
        reset()
    }

    func onDisappear() {
        camera.stop()
        cancellables.removeAll()
    }

    private func bindFrames() {
        camera.frames
            // Throttle detection to a few times per second to save battery.
            .throttle(for: .milliseconds(120), scheduler: DispatchQueue.global(qos: .userInitiated), latest: true)
            .sink { [weak self] buffer in
                Task { await self?.handleFrame(buffer) }
            }
            .store(in: &cancellables)
    }

    private func handleFrame(_ buffer: CVPixelBuffer) async {
        // Stop detecting once we're capturing/analyzing/showing a result.
        switch phase {
        case .searching, .locked: break
        default: return
        }
        guard !isDetecting, !isCapturing else { return }
        isDetecting = true
        defer { isDetecting = false }

        let candidates = await detector.detectCandidates(in: buffer)
        // The tracker picks ONE card and sticks with it across frames.
        let stable = tracker.update(with: candidates)
        detectedCard = stable

        guard let card = stable else {
            // Lost the card → reset all gating state.
            phase = .searching
            resetAutoCaptureState()
            return
        }
        phase = .locked

        // Condition 2: the card's center must stop moving.
        updatePositionStability(for: card)

        // Condition 1: read the bottom set number live and confirm it looks
        // like a valid card. Only run while position is settling to save work.
        await updateSetNumber(buffer: buffer, card: card)

        evaluateAutoCapture(card: card)
    }

    /// Tracks the tracked card's centroid; sets `isPositionStable` once it has
    /// moved less than the threshold for several consecutive frames.
    private func updatePositionStability(for card: DetectedCard) {
        let center = card.centroid
        defer { lastCenter = center }
        guard let previous = lastCenter else {
            stableFrameCount = 0
            isPositionStable = false
            return
        }
        let delta = hypot(center.x - previous.x, center.y - previous.y)
        if delta <= centerStabilityThreshold {
            stableFrameCount += 1
        } else {
            stableFrameCount = 0
        }
        isPositionStable = stableFrameCount >= stableFramesRequired
    }

    /// Lightweight live OCR of the card region to find a valid set number.
    private func updateSetNumber(buffer: CVPixelBuffer, card: DetectedCard) async {
        guard !isReadingLive, !hasValidSetNumber else { return }
        isReadingLive = true
        defer { isReadingLive = false }

        // Dewarp the current frame's card region, then OCR just that crop.
        nonisolated(unsafe) let safeBuffer = buffer
        guard let cg = Self.makeCGImage(from: safeBuffer),
              let region = PerspectiveCorrector.correctedCard(from: cg, card: card) else { return }

        let text: RecognizedText
        if let lang = selectedLanguage {
            text = await recognizer.recognize(in: region, languages: [lang])
        } else {
            text = await recognizer.recognize(in: region)
        }
        if let setNo = validator.setNumber(in: text),
           validator.validate(text).isLikelyPokemonCard {
            liveSetNumber = setNo
            hasValidSetNumber = true
        }
    }

    /// Auto-captures when BOTH conditions hold:
    ///  1. a valid set number was read (valid Pokémon card), and
    ///  2. the card's center position is stable.
    private func evaluateAutoCapture(card: DetectedCard) {
        guard case .locked = phase, !isCapturing else { return }
        guard hasValidSetNumber, isPositionStable else { return }
        Task { await autoCapture(card: card) }
    }

    private func resetAutoCaptureState() {
        lastCenter = nil
        stableFrameCount = 0
        isPositionStable = false
        hasValidSetNumber = false
        liveSetNumber = nil
    }

    /// Converts a pixel buffer to a CGImage for live OCR.
    private static func makeCGImage(from buffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        return ciContext.createCGImage(ci, from: ci.extent)
    }

    // MARK: - Capture & validate

    /// Manual shutter (still available as a fallback). Uses the tracked card.
    func captureAndValidate() async {
        guard case .locked = phase, let card = detectedCard else { return }
        await autoCapture(card: card)
    }

    /// Captures a still, dewarps the card to a front-facing crop, shows it
    /// centered, then runs OCR validation.
    private func autoCapture(card: DetectedCard) async {
        guard !isCapturing else { return }
        isCapturing = true
        phase = .analyzing
        defer { isCapturing = false }

        guard let full = await camera.capturePhoto() else {
            phase = .locked
            return
        }

        // Perspective-correct the tilted card into a flat, upright image.
        let corrected = PerspectiveCorrector.correctedCard(from: full, card: card)
            ?? Self.uprightPortrait(crop(full, to: card) ?? full)
            ?? full

        correctedCard = corrected
        lastCapturedImage = corrected

        let text: RecognizedText
        if let lang = selectedLanguage {
            text = await recognizer.recognize(in: corrected, languages: [lang])
        } else {
            text = await recognizer.recognize(in: corrected)
        }
        recognizedLanguage = text.detectedLanguage
        let validation = validator.validate(text)
        phase = .result(validation)
    }

    /// Re-runs OCR on the already-captured card image, forcing a single
    /// language. Used when the auto-detected language was wrong.
    func reread(in language: OCRLanguage) async {
        guard let image = lastCapturedImage, !isRereading else { return }
        isRereading = true
        defer { isRereading = false }

        let text = await recognizer.recognize(in: image, languages: [language])
        recognizedLanguage = language
        let validation = validator.validate(text)
        phase = .result(validation)
    }

    /// Persists the last capture to the user's collection and kicks off a
    /// price estimate. The SwiftData context is passed in from the view.
    func save(validation: CardValidation, into context: ModelContext) async {
        let fileName = lastCapturedImage.flatMap { ImageStore.save($0) }
        let card = CollectedCard(
            name: validation.detectedName ?? "Unknown card",
            setNumber: validation.detectedSetNumber,
            imageFileName: fileName,
            detectionConfidence: validation.confidence
        )
        context.insert(card)

        // Best-effort price estimate; failures are non-fatal.
        if let estimate = try? await priceEstimator.estimate(
            for: PriceQuery(name: card.name, setNumber: card.setNumber)
        ) ?? nil {
            card.estimatedPriceCents = estimate.amountCents
            card.priceCurrency = estimate.currency
        }
        try? context.save()
    }

    func reset() {
        phase = .searching
        detectedCard = nil
        lastCapturedImage = nil
        correctedCard = nil
        recognizedLanguage = nil
        resetAutoCaptureState()
        tracker.reset()
    }

    /// Rotates a raw back-camera image (sensor/landscape orientation) to
    /// upright portrait. `.right` is the EXIF orientation of a back-camera
    /// frame when the phone is held in portrait.
    private static let ciContext = CIContext()
    private static func uprightPortrait(_ image: CGImage) -> CGImage? {
        let oriented = CIImage(cgImage: image).oriented(.right)
        return ciContext.createCGImage(oriented, from: oriented.extent)
    }

    /// Crops the full photo to the detected quad's bounding box (axis-aligned).
    /// A production build could perspective-correct here; bounding box keeps
    /// the dependency surface small and is enough for OCR.
    private func crop(_ image: CGImage, to card: DetectedCard?) -> CGImage? {
        guard let card else { return nil }
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        // Vision coords: origin bottom-left, normalized. Convert to image px
        // (origin top-left).
        let xs = card.normalizedCorners.map { $0.x * w }
        let ys = card.normalizedCorners.map { (1 - $0.y) * h }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -8, dy: -8)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        return image.cropping(to: rect)
    }
}
