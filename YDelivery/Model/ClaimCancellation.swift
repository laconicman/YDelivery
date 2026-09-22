import Foundation
import YDeliveryKit

/// The live answer to "can this order still be cancelled, and what does it cost" —
/// status, version, and terms asked together, because all three move while the courier
/// does. The `version` rides along because the cancel call must name the claim's
/// current one; trusting what history remembers risks refusing a claim that has since
/// moved on.
nonisolated struct ClaimCancellation: Hashable, Sendable {
    /// Where the claim stood at the moment of asking.
    var status: PlacedClaim.Progress
    /// The claim's current version — `cancelClaim` demands it verbatim.
    var version: Int
    /// What the provider will let this cancellation cost.
    var terms: Terms

    /// The wire's `cancel_state`, in the sender's terms. `paid` keeps its money as
    /// parsed values — the price the provider names is with VAT (`price_with_vat`),
    /// the field every other money read in this app already prefers.
    nonisolated enum Terms: Hashable, Sendable {
        /// No charge — the courier has not reached the pickup point.
        case free
        /// The courier is en route; cancelling costs the named price, or an
        /// unnamed one when the provider kept it to itself.
        case paid(price: Decimal?, currency: String?)
        /// Past the wire's last boundary — only support can close this claim.
        case unavailable
    }
}

nonisolated extension ClaimCancellation.Terms {
    /// Whether the sender can consent to these terms at all — `free` always,
    /// `paid` only once it names its amount: a charge nobody has seen is not a
    /// price anyone can agree to (review, PR #32). The button and the model's
    /// second guard both key off this.
    var isConfirmable: Bool {
        switch self {
        case .free: true
        case .paid(let price, _): price != nil
        case .unavailable: false
        }
    }

    /// The sentence the cancel button carries — the price on it is the consent,
    /// so a paid cancellation names its number or admits it doesn't have one.
    var buttonTitle: String {
        switch self {
        case .free:
            return String(localized: "Cancel this delivery — free")
        case .paid(let price, let currency):
            guard let price else { return String(localized: "Cancel this delivery — paid") }
            let amount = price.formatted(.currency(code: currency ?? "RUB"))
            return String(localized: "Cancel this delivery — pay \(amount)")
        case .unavailable:
            return String(localized: "Cancel this delivery")
        }
    }

    /// What the cancellation costs, as a sentence above the button.
    var explanation: String {
        switch self {
        case .free:
            return String(localized: "Cancelling is free — the courier has not reached the pickup point.")
        case .paid(let price, let currency):
            guard let price else {
                return String(localized: "The courier is already on the way — cancelling is paid, but the provider never named the amount. Ask again, or close the order through Yandex support.")
            }
            let amount = price.formatted(.currency(code: currency ?? "RUB"))
            return String(localized: "The courier is already on the way — cancelling costs \(amount).")
        case .unavailable:
            return String(localized: "The courier already has the parcel — this order can only be closed through Yandex support.")
        }
    }
}

/// Thrown when a cancel is attempted on terms that said `unavailable` — or terms that
/// went stale between the asking and the answering. A refusal the sender can read.
nonisolated struct ClaimUncancellable: LocalizedError, Hashable {
    var errorDescription: String? {
        String(localized: "This order can no longer be cancelled.")
    }
}

/// A `paid` term without its amount is refused at the boundary too — nobody can
/// consent to a price they never saw. The screen's `isConfirmable` gate is the
/// first guard; this is the second (review, PR #32).
nonisolated struct CancellationPriceUnknown: LocalizedError, Hashable {
    var errorDescription: String? {
        String(localized: "The provider never named the cancellation price — ask again, or close the order through Yandex support.")
    }
}

/// The cancel call answered 200 but the claim's status is not a cancelled one — the
/// wire kept the claim standing. Named rather than generic so the sentence it renders
/// says exactly that.
nonisolated struct CancellationUnconfirmed: LocalizedError, Hashable {
    var status: String
    var errorDescription: String? {
        String(localized: "The provider answered, but the claim was not cancelled (\(status)).")
    }
}

nonisolated extension Order {
    /// Whether cancelling is worth offering at all: a claim id exists and nothing
    /// local calls the order finished. The wire refines the answer — the terms fetch
    /// can still come back `unavailable`, and that is the point of asking it.
    var isCancellable: Bool {
        claimID != nil && (status == .searching || status == .active)
    }
}
