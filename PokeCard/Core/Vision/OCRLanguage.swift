//
//  OCRLanguage.swift
//  PokeCard
//
//  The set of languages the card OCR supports, shared by the recognizer and
//  the UI so they always agree.
//

import Foundation

enum OCRLanguage: String, CaseIterable, Identifiable, Equatable {
    case english = "en-US"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var id: String { rawValue }

    /// Vision recognition-language code.
    var visionCode: String { rawValue }

    /// Short, localized-ish display name for the UI.
    var displayName: String {
        switch self {
        case .english:  return "English"
        case .japanese: return "日本語"
        case .korean:   return "한국어"
        }
    }

    var flag: String {
        switch self {
        case .english:  return "🇺🇸"
        case .japanese: return "🇯🇵"
        case .korean:   return "🇰🇷"
        }
    }
}
