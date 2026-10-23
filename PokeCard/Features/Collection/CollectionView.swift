//
//  CollectionView.swift
//  PokeCard
//
//  Displays the user's saved cards in a cute grid, backed by SwiftData.
//

import SwiftUI
import SwiftData

struct CollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CollectedCard.dateAdded, order: .reverse) private var cards: [CollectedCard]

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if cards.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(cards) { card in
                            NavigationLink {
                                CardDetailView(card: card)
                            } label: {
                                CardCell(card: card)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    delete(card)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("My Collection")
        .navigationBarTitleDisplayMode(.large)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MascotBadge(size: 76)
            Text("No cards yet")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Scan a card to start your collection!")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
    }

    private func delete(_ card: CollectedCard) {
        ImageStore.delete(card.imageFileName)
        modelContext.delete(card)
        try? modelContext.save()
    }
}

private struct CardCell: View {
    let card: CollectedCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let set = card.setNumber {
                    // e.g. "[G] 001/198 ●" — mark and rarity only if detected.
                    Text([
                        card.regulationMark.map { "[\($0)]" },
                        set,
                        card.rarityPrinted ?? card.rarity.map { $0.symbol ?? $0.rawValue }
                    ].compactMap { $0 }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(card.formattedPrice)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.primary.opacity(0.12), radius: 8, x: 0, y: 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = ImageStore.loadUIImage(card.imageFileName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(0.716, contentMode: .fill)
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.secondary.opacity(0.18))
                .frame(height: 170)
                .overlay(
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.secondary)
                )
        }
    }
}

#Preview {
    NavigationStack {
        CollectionView()
    }
    .modelContainer(for: CollectedCard.self, inMemory: true)
}
