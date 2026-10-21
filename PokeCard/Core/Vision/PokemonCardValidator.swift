//
//  PokemonCardValidator.swift
//  PokeCard
//
//  Decides whether OCR text from a cropped image looks like a Pokémon trading
//  card. This relies on *factual, structural* markers (HP labels, energy-type
//  words, set numbers like "123/198", the "Illus." credit line, etc.) that are
//  not themselves copyrightable. We do NOT compare against copyrighted artwork.
//

import Foundation

struct CardValidation: Equatable {
    let isLikelyPokemonCard: Bool
    let confidence: Double            // 0...1 heuristic score
    let detectedName: String?         // best-guess card name (factual data)
    let detectedSetNumber: String?    // e.g. "123/198"
    let matchedSignals: [String]      // which markers fired (for debugging/UI)
}

struct PokemonCardValidator {

    /// Structural markers commonly printed on Pokémon TCG cards, across the
    /// English, Japanese, and Korean prints. These are generic terms / symbols,
    /// not creative expression.
    private let keywords: [String] = [
        // English
        "HP", "Weakness", "Resistance", "Retreat", "Illus",
        "Basic", "Stage 1", "Stage 2", "Trainer", "Energy",
        "Pokémon", "Pokemon",
        // Japanese
        "ワザ", "にげる", "弱点", "抵抗力", "進化", "たね",
        "トレーナー", "エネルギー", "ポケモン",
        // Korean
        "약점", "저항력", "진화", "트레이너", "에너지", "포켓몬",
        "기본", "도망"
    ]

    private let energyTypes: [String] = [
        // English
        "Grass", "Fire", "Water", "Lightning", "Psychic",
        "Fighting", "Darkness", "Metal", "Fairy", "Dragon", "Colorless",
        // Japanese
        "草", "炎", "水", "雷", "超", "闘", "悪", "鋼", "妖", "龍", "無",
        // Korean
        "풀", "불꽃", "물", "번개", "초능력", "격투", "악", "강철", "페어리", "드래곤", "무색"
    ]

    // Set number like "123/198", "SV01 045/198", or "001/081C" (with an
    // optional trailing letter used by some sets).
    private let setNumberPattern = #"\b\d{1,3}\s?/\s?\d{1,3}[A-Za-z]?\b"#

    /// Extracts the card's set number from recognized text, if present.
    /// Lightweight — safe to call on live frames for auto-capture gating.
    func setNumber(in text: RecognizedText) -> String? {
        firstMatch(of: setNumberPattern, in: text.joined)
    }

    func validate(_ text: RecognizedText) -> CardValidation {
        let haystack = text.joined
        var score = 0.0
        var signals: [String] = []

        for kw in keywords where haystack.localizedCaseInsensitiveContains(kw) {
            score += 0.12
            signals.append(kw)
        }
        for et in energyTypes where haystack.localizedCaseInsensitiveContains(et) {
            score += 0.08
            signals.append("type:\(et)")
        }

        let setNumber = firstMatch(of: setNumberPattern, in: haystack)
        if let setNumber {
            score += 0.3
            signals.append("setNumber:\(setNumber)")
        }

        // "HP" followed by digits is a very strong signal.
        if firstMatch(of: #"\bHP\s?\d{1,3}\b"#, in: haystack) != nil ||
           firstMatch(of: #"\b\d{1,3}\s?HP\b"#, in: haystack) != nil {
            score += 0.25
            signals.append("HP+number")
        }

        score = min(score, 1.0)

        return CardValidation(
            isLikelyPokemonCard: score >= 0.5,
            confidence: score,
            detectedName: guessName(from: text),
            detectedSetNumber: setNumber,
            matchedSignals: signals
        )
    }

    /// Heuristic: the card name is usually the top-most prominent short line
    /// that isn't a pure number/keyword. This is a best-effort factual guess.
    private func guessName(from text: RecognizedText) -> String? {
        for line in text.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3, trimmed.count <= 24 else { continue }
            if keywords.contains(where: { trimmed.localizedCaseInsensitiveContains($0) }) { continue }
            if trimmed.rangeOfCharacter(from: .decimalDigits) != nil && trimmed.count <= 6 { continue }
            return trimmed
        }
        return nil
    }

    private func firstMatch(of pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r]).trimmingCharacters(in: .whitespaces)
    }
}
