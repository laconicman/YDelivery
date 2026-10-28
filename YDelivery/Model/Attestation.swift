import Foundation
import YDeliveryKit

// The app's side of the trust layer's read values (doc:Collaboration → "Verdicts and
// entitlement"): plain values the controller hands to views, never a CloudKit name.

/// An order's two derived verdicts, read together: the mirror's status and the
/// stored route, each against the latest verified fact (doc:Schema → "Derived
/// integrity").
nonisolated struct OrderIntegrity: Hashable, Sendable {
    var mirror: IntegrityVerdict
    var route: IntegrityVerdict
}

nonisolated extension Verdict {
    /// The verdict with the author's name taken out — what an unshared order shows:
    /// its device is its owner, and nobody else is there to name (the #92 lesson,
    /// doc:Collaboration).
    var withoutNames: Verdict {
        switch self {
        case .verified(var author):
            author.displayName = nil
            return .verified(author: author)
        case .notEntitled(var author):
            author.displayName = nil
            return .notEntitled(author: author)
        case .legacy, .unsigned, .invalid, .untrustedKey, .unverifiable:
            return self
        }
    }

    /// The case's name for the diagnostics line — an identifier, never a name or a
    /// payload.
    var diagnosticName: String {
        switch self {
        case .verified: "verified"
        case .legacy: "legacy"
        case .unsigned: "unsigned"
        case .invalid: "invalid"
        case .untrustedKey: "untrustedKey"
        case .unverifiable: "unverifiable"
        case .notEntitled: "notEntitled"
        }
    }
}

nonisolated extension Attested {
    /// The row with its verdict's names taken out (``Verdict/withoutNames``).
    var withoutNames: Attested {
        Attested(value: value, verdict: verdict.withoutNames)
    }
}
