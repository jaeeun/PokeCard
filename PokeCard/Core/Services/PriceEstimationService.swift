//
//  PriceEstimationService.swift
//  PokeCard
//
//  Abstraction for estimating a card's market price.
//
//  LICENSING / DATA SOURCING NOTE
//  Prices are FACTUAL data and not copyrightable, but each price API has its
//  own Terms of Service. When wiring a real provider (e.g. TCGplayer,
//  PriceCharting, Pokémon TCG API), you MUST:
//    • Use an official/public API with a key where required.
//    • Respect rate limits and attribution requirements in their ToS.
//    • Avoid scraping sites that prohibit it.
//  Keep the API key out of source control (use Secrets.xcconfig / Keychain).
//

import Foundation

struct PriceQuery {
    let name: String
    let setNumber: String?
}

struct PriceEstimate: Equatable {
    let amountCents: Int
    let currency: String
    let source: String
    let asOf: Date
}

protocol PriceEstimating {
    func estimate(for query: PriceQuery) async throws -> PriceEstimate?
}

/// Placeholder implementation. Returns a deterministic pseudo-estimate so the
/// UI can be built and demoed before a real pricing API is connected.
///
/// Replace with a concrete provider implementation (see note above).
struct StubPriceEstimator: PriceEstimating {
    func estimate(for query: PriceQuery) async throws -> PriceEstimate? {
        try await Task.sleep(nanoseconds: 400_000_000)
        // Deterministic fake value derived from the name so demos are stable.
        let seed = abs(query.name.hashValue) % 4000 + 100   // 1.00 – 41.00
        return PriceEstimate(
            amountCents: seed,
            currency: "USD",
            source: "stub",
            asOf: .now
        )
    }
}

enum PriceEstimatorFactory {
    static func make() -> PriceEstimating {
        // TODO: return a real provider once an API key is configured.
        StubPriceEstimator()
    }
}
