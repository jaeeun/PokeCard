//
//  CollectedCard.swift
//  PokeCard
//
//  SwiftData model for a card the user has saved to their collection.
//
//  LICENSING: we store only the user's own photo (local file) and FACTUAL
//  metadata derived via OCR (name, set number). We never store or bundle
//  official artwork from any third party.
//

import Foundation
import SwiftData

@Model
final class CollectedCard {
    @Attribute(.unique) var id: UUID
    var name: String
    var setNumber: String?
    /// Single-letter regulation mark printed next to the set number (e.g. "G").
    var regulationMark: String?
    /// `CardRarity` raw code (e.g. "C", "RR", "SAR"); nil if not detected.
    var rarityCode: String?
    /// Rarity exactly as printed: "C" (JP/KR letter code) or "●" (EN symbol).
    var rarityPrinted: String?
    /// Filename of the user-captured image stored in the app's sandbox.
    var imageFileName: String?
    /// Last price estimate in minor units (e.g. cents), nil if unknown.
    var estimatedPriceCents: Int?
    var priceCurrency: String
    var dateAdded: Date
    /// OCR confidence 0...1 that this is a valid card.
    var detectionConfidence: Double

    init(
        id: UUID = UUID(),
        name: String,
        setNumber: String? = nil,
        regulationMark: String? = nil,
        rarity: RarityReading? = nil,
        imageFileName: String? = nil,
        estimatedPriceCents: Int? = nil,
        priceCurrency: String = "USD",
        dateAdded: Date = .now,
        detectionConfidence: Double = 0
    ) {
        self.id = id
        self.name = name
        self.setNumber = setNumber
        self.regulationMark = regulationMark
        self.rarityCode = rarity?.rarity.rawValue
        self.rarityPrinted = rarity?.printed
        self.imageFileName = imageFileName
        self.estimatedPriceCents = estimatedPriceCents
        self.priceCurrency = priceCurrency
        self.dateAdded = dateAdded
        self.detectionConfidence = detectionConfidence
    }

    var rarity: CardRarity? { rarityCode.flatMap(CardRarity.init(rawValue:)) }

    /// e.g. "C · Common" or "● Common"; nil if no rarity was detected.
    var rarityLabel: String? { rarity?.label(printed: rarityPrinted) }

    var formattedPrice: String {
        guard let cents = estimatedPriceCents else { return "—" }
        let amount = Double(cents) / 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = priceCurrency
        return formatter.string(from: NSNumber(value: amount)) ?? "—"
    }
}
