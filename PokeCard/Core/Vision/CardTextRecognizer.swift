//
//  CardTextRecognizer.swift
//  PokeCard
//
//  On-device OCR using Vision's VNRecognizeTextRequest. We extract raw text
//  lines from a cropped card image, which the validator then inspects for
//  factual markers of a trading card.
//

import Foundation
import Vision
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

struct RecognizedText: Equatable {
    let lines: [String]
    /// The language(s) the OCR request was configured to read with.
    let requestedLanguages: [OCRLanguage]
    /// Best guess of the dominant language of the text, from its script.
    let detectedLanguage: OCRLanguage?

    var joined: String { lines.joined(separator: "\n") }

    init(lines: [String],
         requestedLanguages: [OCRLanguage] = [],
         detectedLanguage: OCRLanguage? = nil) {
        self.lines = lines
        self.requestedLanguages = requestedLanguages
        self.detectedLanguage = detectedLanguage ?? RecognizedText.inferLanguage(from: lines)
    }

    /// Infers the dominant script of the recognized text: Hangul → Korean,
    /// Kana → Japanese, otherwise (if any Latin letters) English.
    static func inferLanguage(from lines: [String]) -> OCRLanguage? {
        var hangul = 0, kana = 0, latin = 0
        for scalar in lines.joined().unicodeScalars {
            switch scalar.value {
            case 0xAC00...0xD7A3, 0x1100...0x11FF:           // Hangul
                hangul += 1
            case 0x3040...0x309F, 0x30A0...0x30FF:           // Hiragana + Katakana
                kana += 1
            case 0x41...0x5A, 0x61...0x7A:                   // Basic Latin letters
                latin += 1
            default:
                break
            }
        }
        if hangul == 0 && kana == 0 && latin == 0 { return nil }
        if hangul >= kana && hangul >= latin { return .korean }
        if kana >= hangul && kana >= latin { return .japanese }
        return .english
    }
}

final class CardTextRecognizer {

    /// Languages we'd like to read on cards: English, Japanese, Korean.
    private let defaultLanguages: [OCRLanguage] = [.english, .japanese, .korean]

    /// Recognize using the default multilingual set (auto).
    func recognize(in cgImage: CGImage) async -> RecognizedText {
        await recognize(in: cgImage, languages: defaultLanguages)
    }

    /// Recognize using a specific language set (used for the user-driven
    /// "re-read in this language" action).
    func recognize(in cgImage: CGImage, languages: [OCRLanguage]) async -> RecognizedText {
        await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                // If the user forced a single language, report that; otherwise
                // infer from the script.
                let detected: OCRLanguage? = languages.count == 1 ? languages.first : nil
                continuation.resume(returning: RecognizedText(
                    lines: lines,
                    requestedLanguages: languages,
                    detectedLanguage: detected
                ))
            }
            // Japanese & Korean OCR require the `.accurate` level; `.fast`
            // supports Latin scripts only.
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            // Only request languages this device/OS actually supports.
            let supported = (try? request.supportedRecognitionLanguages()) ?? []
            let langs = languages.map(\.visionCode).filter(supported.contains)
            if !langs.isEmpty {
                request.recognitionLanguages = langs
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: RecognizedText(
                    lines: [], requestedLanguages: languages
                ))
            }
        }
    }

    #if canImport(UIKit)
    func recognize(in image: UIImage) async -> RecognizedText {
        guard let cg = image.cgImage else { return RecognizedText(lines: []) }
        return await recognize(in: cg)
    }
    #endif
}
