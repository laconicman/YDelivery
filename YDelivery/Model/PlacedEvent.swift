import Foundation
import YDeliveryKit

/// The agreed terms the `placed` fact carries in `detail` — claim, tariff, price,
/// currency, as the sender accepted them (doc:Collaboration → "`routeDigest`").
/// Encoded with sorted keys: `detail` is signed, so the same terms must always be the
/// same bytes.
nonisolated struct PlacedTerms: Codable, Hashable, Sendable {
    var claimID: String
    var tariff: String?
    var price: String?
    var currency: String?
}

nonisolated extension OrderEvent {
    /// The ordering flow's own fact for an order it just placed: kind `placed`,
    /// source `app`, the agreed terms as JSON in `detail`, and the digest of the route
    /// as sent. Stamped with the `updated_ts` and `revision` of the last claim card the
    /// flow read before accepting — provider time, never the device's clock
    /// (doc:Schema → "Epoch 2") — so without a card there is no fact to write. It
    /// carries no `providerStatus`: it is a digest-bearing row, not a status
    /// observation, and must never compete with the mirror's status.
    static func placed(_ order: Order, observed: PlacedClaim.Observation?) -> OrderEvent? {
        guard let observed, let claimID = order.claimID else { return nil }
        let terms = PlacedTerms(
            claimID: claimID, tariff: order.tariff, price: order.price, currency: order.currency)
        return OrderEvent(
            orderID: order.id,
            providerRevision: observed.revision,
            at: observed.at,
            kind: Kind.placed,
            detail: PlacedTerms.json(terms),
            source: Source.app,
            routeDigest: CanonicalPayload.routeDigest(for: order.route))
    }
}

nonisolated extension PlacedTerms {
    /// The terms as the `detail` string — `nil` only if encoding a struct of strings
    /// could fail, which it cannot; the optional keeps `try!` out of app code.
    static func json(_ terms: PlacedTerms) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(terms)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
