//
//  ScannerView.swift
//  PokeCard
//
//  Live camera scanning screen with the rounded guiding overlay and a
//  capture button that triggers OCR validation.
//

import SwiftUI
import SwiftData
import AVFoundation

struct ScannerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var vm = ScannerViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if vm.permissionDenied {
                permissionDeniedView
            } else {
                // The overlay is attached to the preview with `.overlay`, so
                // both share the exact same frame and coordinate space.
                CameraPreview(previewLayer: vm.camera.previewLayer)
                    .overlay {
                        if vm.selectedLanguage != nil {
                            CardGuideOverlay(
                                viewCorners: viewCorners(),
                                isValidated: isValidated
                            )
                        }
                    }
                    .overlay { steadinessRing }
                    .ignoresSafeArea()

                if vm.selectedLanguage == nil {
                    // Ask the user to choose a scan language first.
                    languagePicker
                } else {
                    // The perspective-corrected card plus its result panel.
                    if let corrected = vm.correctedCard, case let .result(validation) = vm.phase {
                        resultOverlay(card: corrected, validation: validation)
                    } else if let corrected = vm.correctedCard {
                        centeredCard(corrected)
                    }

                    VStack {
                        statusBar
                        Spacer()
                        controls
                    }
                    .padding(.vertical, 24)
                }
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.onAppear() }
        .onDisappear { vm.onDisappear() }
    }

    // MARK: - Language selection

    /// Full-screen prompt to pick the card's language before scanning starts.
    private var languagePicker: some View {
        ZStack {
            Color.black.opacity(0.78).ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "character.book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.accent)
                    Text("Which language is the card?")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Pick the printed language for the most accurate scan.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    ForEach(OCRLanguage.allCases) { lang in
                        Button {
                            vm.startScanning(language: lang)
                        } label: {
                            HStack(spacing: 14) {
                                Text(lang.flag).font(.title)
                                Text(lang.displayName)
                                    .font(.headline.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20).padding(.vertical, 16)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(28)
        }
    }

    /// Status pill plus a chip showing the chosen language (tap to change).
    private var statusBar: some View {
        HStack(spacing: 10) {
            statusPill
            if let lang = vm.selectedLanguage {
                Button {
                    vm.changeLanguage()
                } label: {
                    HStack(spacing: 4) {
                        Text(lang.flag)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - Captured card + result (no overlap)

    /// Card image anchored near the top; the result panel sits beneath it.
    private func resultOverlay(card: CGImage, validation: CardValidation) -> some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 20) {
                cardImage(card)
                    .frame(maxWidth: 260, maxHeight: 360)
                    .padding(.top, 12)

                ScanResultPanel(
                    validation: validation,
                    recognizedLanguage: vm.recognizedLanguage,
                    isRereading: vm.isRereading,
                    onReread: { language in await vm.reread(in: language) },
                    onSave: { await vm.save(validation: validation, into: modelContext) },
                    onDismiss: { vm.reset() }
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .transition(.opacity)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.correctedCard != nil)
    }

    // MARK: - Centered corrected card

    private func centeredCard(_ image: CGImage) -> some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            cardImage(image)
                .frame(maxWidth: 300, maxHeight: 440)
                .transition(.scale.combined(with: .opacity))
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.correctedCard != nil)
    }

    /// Shared, styled rendering of a captured card image.
    private func cardImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1, orientation: .up)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }

    /// Shows the two auto-capture conditions and their live status while a card
    /// is locked: (1) a valid set number is read, (2) the card is steady.
    @ViewBuilder private var steadinessRing: some View {
        if case .locked = vm.phase {
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    conditionRow(
                        done: vm.liveSetNumber != nil,
                        text: vm.liveSetNumber.map { "Set number: \($0)" } ?? "Reading set number…"
                    )
                    conditionRow(
                        done: vm.isPositionStable,
                        text: vm.isPositionStable ? "Card steady" : "Hold the card still…"
                    )
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.bottom, 140)
            }
        }
    }

    private func conditionRow(done: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(done ? Theme.mint : .white.opacity(0.7))
            Text(text)
                .foregroundStyle(.white)
        }
        .font(.footnote.weight(.semibold))
    }

    // MARK: - Derived UI state

    private var isValidated: Bool {
        if case let .result(v) = vm.phase { return v.isLikelyPokemonCard }
        return false
    }

    /// Map the detected card onto the screen via the preview layer itself,
    /// which knows the real rotation and aspect-fill crop of what's displayed.
    private func viewCorners() -> [CGPoint]? {
        guard let card = vm.detectedCard else { return nil }
        let layer = vm.camera.previewLayer
        guard layer.bounds.width > 0, layer.bounds.height > 0 else { return nil }
        return layer.layerPoints(forVisionCorners: card.normalizedCorners)
    }

    // MARK: - Subviews

    private var statusPill: some View {
        Text(statusText)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 8)
    }

    private var statusText: String {
        switch vm.phase {
        case .searching: return "Looking for a card…"
        case .locked:    return "Align the card — auto-capturing…"
        case .analyzing: return "Reading card…"
        case .result:    return "Done"
        }
    }

    private var controls: some View {
        shutterControls
    }

    @ViewBuilder private var shutterControls: some View {
        // Hide the shutter while reviewing a captured image (analyzing/result).
        if showShutter {
            Button {
                Task { await vm.captureAndValidate() }
            } label: {
                ZStack {
                    Circle().fill(.white).frame(width: 76, height: 76)
                    Circle().stroke(Theme.primary, lineWidth: 5).frame(width: 86, height: 86)
                }
            }
            .disabled(disableCapture)
            .opacity(disableCapture ? 0.5 : 1)
            .padding(.bottom, 12)
        }
    }

    /// Shutter is only shown while actively scanning (not while reviewing a
    /// captured card).
    private var showShutter: Bool {
        switch vm.phase {
        case .searching, .locked: return true
        case .analyzing, .result: return false
        }
    }

    private var disableCapture: Bool {
        switch vm.phase {
        case .locked: return false
        default: return true
        }
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.white)
            Text("Camera access is required to scan cards.")
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.cute)
            .frame(maxWidth: 240)
        }
        .padding()
    }
}

/// Result panel shown beneath the captured card (not a full sheet, so it
/// never covers the card image).
private struct ScanResultPanel: View {
    let validation: CardValidation
    let recognizedLanguage: OCRLanguage?
    let isRereading: Bool
    let onReread: (OCRLanguage) async -> Void
    let onSave: () async -> Void
    let onDismiss: () -> Void

    @State private var isSaving = false
    @State private var didSave = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: validation.isLikelyPokemonCard ? "checkmark.seal.fill" : "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(validation.isLikelyPokemonCard ? Theme.mint : Theme.accent)
                Text(validation.isLikelyPokemonCard ? "Looks like a Pokémon card!" : "Not sure about this one")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
            }

            if let name = validation.detectedName {
                labelRow("Name", name)
            }
            if let set = validation.detectedSetNumber {
                labelRow("Set #", set)
            }
            labelRow("Confidence", String(format: "%.0f%%", validation.confidence * 100))

            languageSection

            if didSave {
                Label("Saved to collection", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.mint)
                    .font(.subheadline.weight(.semibold))
                Button("Scan again", action: onDismiss)
                    .buttonStyle(.cute(fill: Theme.secondary))
            } else {
                Button {
                    Task {
                        isSaving = true
                        await onSave()
                        isSaving = false
                        didSave = true
                    }
                } label: {
                    if isSaving { ProgressView().tint(.white) }
                    else { Text("Save to collection") }
                }
                .buttonStyle(.cute)
                .disabled(isSaving)

                Button("Scan again", action: onDismiss)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
    }

    private func labelRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).fontWeight(.semibold).foregroundStyle(Theme.textPrimary)
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
    }

    /// Shows which language the card was read in, and lets the user re-read the
    /// captured image in a different language if detection was wrong.
    @ViewBuilder private var languageSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Read in")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let lang = recognizedLanguage {
                    Text("\(lang.flag) \(lang.displayName)")
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Text("Unknown")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 8)

            // Wrong language? Re-read the captured image in another one.
            HStack(spacing: 8) {
                Text("Re-read:")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(OCRLanguage.allCases) { lang in
                    Button {
                        Task { await onReread(lang) }
                    } label: {
                        Text("\(lang.flag) \(lang.displayName)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                (recognizedLanguage == lang ? Theme.primary.opacity(0.18) : Theme.secondary.opacity(0.12)),
                                in: Capsule()
                            )
                            .foregroundStyle(recognizedLanguage == lang ? Theme.primary : Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRereading)
                }
                if isRereading {
                    ProgressView().scaleEffect(0.7)
                }
            }
        }
        .padding(.top, 4)
    }
}

#Preview {
    NavigationStack {
        ScannerView()
            .environmentObject(AppState(authService: PreviewAuthService(signedIn: true)))
    }
}
