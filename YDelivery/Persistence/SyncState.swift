import Foundation

/// The claims sync's small memory: the journal's opaque position, verbatim, plus
/// whether the one-time history backfill already ran — now rows in `syncStates` and
/// `pendingDiscoveries` rather than a file beside the store. Wiped on the identity
/// boundary: the next token never inherits this account's position.
nonisolated struct SyncState: Hashable, Sendable {
    /// The provider's next-page token — a JWT on the wire today, but nothing
    /// here decodes it (the package's own convention, 0.3.0).
    var cursor: String?
    /// Whether `state: finished` has been paged through once — the deep
    /// membership pass that discovers claims predating the cursor. The flag,
    /// not a timestamp, is what survives.
    var historyBackfilled: Bool
    /// Claims the journal reported but whose card fetch failed — the cursor
    /// moved past their events, so this queue is the only memory of them
    /// until a retry or a search pass lands the card (review, PR #35).
    var pendingClaimIDs: [String]? = nil

    /// The `syncStates.providerAccountRef` this device reads and writes until a
    /// credential's `corpClientID` is learned — the table keys on
    /// `"yandex:<corpClientID>"`, and today's sync runs unattributed, same as
    /// migrated orders. Reconciliation re-keys when the account surfaces.
    static let currentAccountRef = "yandex:unattributed"
}
