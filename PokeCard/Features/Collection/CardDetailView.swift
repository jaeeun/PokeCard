//
//  CardDetailView.swift
//  PokeCard
//
//  Full-screen detail for a saved card: a large, zoomable image plus its
//  factual metadata (name, set number, price, date added).
//

import SwiftUI
import SwiftData

struct CardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let card: CollectedCard

    // Pinch-to-zoom + drag-to-pan state for the image.
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    imageViewer
                        .frame(height: 440)
                        .padding(.top, 8)

                    infoCard
                }
                .padding(20)
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.primary)
                }
            }
        }
        .confirmationDialog("Delete this card?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                ImageStore.delete(card.imageFileName)
                modelContext.delete(card)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Zoomable image

    @ViewBuilder
    private var imageViewer: some View {
        if let image = ImageStore.loadUIImage(card.imageFileName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(zoom)
                .offset(offset)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Theme.primary.opacity(0.25), radius: 16, y: 8)
                .gesture(magnification.simultaneously(with: drag))
                .onTapGesture(count: 2) { resetZoom() }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: zoom)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.secondary.opacity(0.18))
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.secondary)
                )
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(lastZoom * value, 1), 5)
            }
            .onEnded { _ in
                lastZoom = zoom
                if zoom <= 1 { resetZoom() }
            }
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in lastOffset = offset }
    }

    private func resetZoom() {
        zoom = 1; lastZoom = 1
        offset = .zero; lastOffset = .zero
    }

    // MARK: - Info

    private var infoCard: some View {
        CuteCard {
            VStack(spacing: 14) {
                infoRow("Name", card.name)
                if let set = card.setNumber { infoRow("Set #", set) }
                infoRow("Estimated price", card.formattedPrice)
                infoRow("Detection", String(format: "%.0f%%", card.detectionConfidence * 100))
                infoRow("Added", card.dateAdded.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

#Preview {
    NavigationStack {
        CardDetailView(card: CollectedCard(
            name: "Sample Card",
            setNumber: "123/198",
            estimatedPriceCents: 1299,
            detectionConfidence: 0.82
        ))
    }
}
