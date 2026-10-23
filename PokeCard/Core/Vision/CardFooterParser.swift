//
//  CardFooterParser.swift
//  PokeCard
//
//  Parses the card's bottom "footer" row, e.g.
//
//      EN/SV:  [G]  SVI EN  001/198  ●
//      JP/KR:  [G]  SV1a    001/073  C
//
//  into its factual parts: the regulation mark (single letter LEFT of the set
//  number), the set number, and — optionally — the rarity (symbol or letter
//  code RIGHT of the set number). These are printed, factual markers only.
//

import Foundation
import CoreGraphics

/// Printed rarity of a card. English prints use symbols (●/◆/★), JP/KR prints
/// use letter codes (C/U/R/RR/SAR…). Raw value is the canonical letter code.
enum CardRarity: String, CaseIterable, Codable, Equatable {
    case common = "C"
    case uncommon = "U"
    case rare = "R"
    case doubleRare = "RR"
    case tripleRare = "RRR"
    case artRare = "AR"
    case superRare = "SR"
    case specialArtRare = "SAR"
    case ultraRare = "UR"
    case hyperRare = "HR"
    case shiny = "S"
    case shinySuperRare = "SSR"
    case aceSpec = "ACE"
    case characterRare = "CHR"
    case characterSuperRare = "CSR"
    case promo = "PR"

    /// The English-print symbol, where one exists.
    var symbol: String? {
        switch self {
        case .common: return "●"
        case .uncommon: return "◆"
        case .rare: return "★"
        case .doubleRare: return "★★"
        case .hyperRare: return "★★★"
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .common: return "Common"
        case .uncommon: return "Uncommon"
        case .rare: return "Rare"
        case .doubleRare: return "Double Rare"
        case .tripleRare: return "Triple Rare"
        case .artRare: return "Art Rare"
        case .superRare: return "Super Rare"
        case .specialArtRare: return "Special Art Rare"
        case .ultraRare: return "Ultra Rare"
        case .hyperRare: return "Hyper Rare"
        case .shiny: return "Shiny"
        case .shinySuperRare: return "Shiny Super Rare"
        case .aceSpec: return "ACE SPEC"
        case .characterRare: return "Character Rare"
        case .characterSuperRare: return "Character Super Rare"
        case .promo: return "Promo"
        }
    }

    /// e.g. "● Common", "SAR · Special Art Rare".
    var label: String {
        if let symbol { return "\(symbol) \(displayName)" }
        return "\(rawValue) · \(displayName)"
    }

    /// Label using the mark exactly as printed on the card, e.g.
    /// "C · Common" (JP/KR) or "● Common" (EN).
    func label(printed: String?) -> String {
        guard let printed, printed != symbol else { return label }
        return "\(printed) · \(displayName)"
    }
}

/// A rarity read from the card, plus how it was printed: a symbol ("●",
/// "★★") on English prints or a letter code ("C", "SAR") on JP/KR prints.
struct RarityReading: Equatable {
    let rarity: CardRarity
    let printed: String

    var label: String { rarity.label(printed: printed) }
}

struct CardFooterInfo: Equatable {
    var setNumber: String?
    var regulationMark: String?
    var rarity: RarityReading?
}

enum CardFooterParser {

    /// Set number with an optional letter suffix glued on by OCR ("001/081C").
    /// Group 1 = set number, group 2 = attached suffix.
    static let setNumberPattern = #"\b(\d{1,3}\s?/\s?\d{1,3})([A-Za-z]{0,3})\b"#

    private static let commonSymbols: Set<Character> = ["●", "•", "⚫", "○", "◯"]
    private static let uncommonSymbols: Set<Character> = ["◆", "♦", "◇", "⬥", "⬦", "❖"]
    private static let starSymbols: Set<Character> = ["★", "☆", "✦", "✧", "⭐", "*"]

    /// Parses footer info, preferring the dedicated footer OCR pass (which has
    /// positions) and falling back to the full-card OCR lines.
    static func parse(footer: [RecognizedLine], fallbackLines: [String]) -> CardFooterInfo {
        var info = parseFooterObservations(footer)
        if info.regulationMark == nil || info.rarity == nil || info.setNumber == nil {
            for line in fallbackLines {
                guard let lineInfo = parseRow(line) else { continue }
                info.setNumber = info.setNumber ?? lineInfo.setNumber
                info.regulationMark = info.regulationMark ?? lineInfo.regulationMark
                info.rarity = info.rarity ?? lineInfo.rarity
                break
            }
        }
        return info
    }

    /// Groups footer observations that sit on the same row as the set number,
    /// orders them left→right, and parses that row as one string. This handles
    /// the common case where Vision returns the boxed regulation mark as its
    /// own observation, separate from the set number.
    static func parseFooterObservations(_ lines: [RecognizedLine]) -> CardFooterInfo {
        guard let anchor = lines.first(where: { firstSetNumberMatch(in: $0.text) != nil }) else {
            return CardFooterInfo()
        }
        let tolerance = max(anchor.boundingBox.height, 0.01) * 0.8
        let row = lines
            .filter { abs($0.boundingBox.midY - anchor.boundingBox.midY) <= tolerance }
            .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .map(\.text)
            .joined(separator: " ")
        return parseRow(row) ?? CardFooterInfo()
    }

    /// Parses a single footer row string. Returns nil if no set number is found.
    static func parseRow(_ row: String) -> CardFooterInfo? {
        guard let match = firstSetNumberMatch(in: row),
              let numberRange = Range(match.range(at: 1), in: row),
              let fullRange = Range(match.range, in: row) else { return nil }

        let setNumber = row[numberRange].replacingOccurrences(of: " ", with: "")
        let attachedSuffix = Range(match.range(at: 2), in: row).map { String(row[$0]) } ?? ""
        let prefix = String(row[..<fullRange.lowerBound])
        let suffix = attachedSuffix + " " + String(row[fullRange.upperBound...])

        return CardFooterInfo(
            setNumber: setNumber,
            regulationMark: regulationMark(in: prefix),
            rarity: rarity(in: suffix)
        )
    }

    /// The regulation mark is a standalone single uppercase letter (often in a
    /// box, which OCR may render as brackets) to the LEFT of the set number.
    static func regulationMark(in prefix: String) -> String? {
        for token in tokens(prefix) {
            let cleaned = token.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if cleaned.count == 1, let c = cleaned.first, c.isASCII, c.isUppercase {
                return String(c)
            }
        }
        return nil
    }

    /// Rarity to the RIGHT of the set number: a symbol (●/◆/★, ★★ …) or a
    /// JP/KR letter code (C, U, R, RR, SAR …). Keeps the printed form.
    static func rarity(in suffix: String) -> RarityReading? {
        let trimmed = suffix.trimmingCharacters(in: .whitespaces)

        // Symbols: only consider the leading run of non-alphanumerics so that
        // unrelated punctuation further along the row doesn't count.
        let leading = trimmed.prefix { !$0.isLetter && !$0.isNumber }
        if leading.contains(where: commonSymbols.contains) {
            return RarityReading(rarity: .common, printed: "●")
        }
        if leading.contains(where: uncommonSymbols.contains) {
            return RarityReading(rarity: .uncommon, printed: "◆")
        }
        let stars = leading.filter(starSymbols.contains).count
        switch stars {
        case 1: return RarityReading(rarity: .rare, printed: "★")
        case 2: return RarityReading(rarity: .doubleRare, printed: "★★")
        case 3...: return RarityReading(rarity: .hyperRare, printed: "★★★")
        default: break
        }

        // Letter codes: the first token after the number (e.g. "123/123 C").
        if let first = tokens(trimmed).first {
            let code = first
                .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                .uppercased()
            if let rarity = CardRarity(rawValue: code) {
                return RarityReading(rarity: rarity, printed: code)
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static let regex = try? NSRegularExpression(pattern: setNumberPattern)

    static func firstSetNumberMatch(in text: String) -> NSTextCheckingResult? {
        regex?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: \.isWhitespace).map(String.init)
    }
}
