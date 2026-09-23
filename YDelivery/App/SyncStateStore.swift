import Foundation

/// The claims sync's small memory: the journal's opaque position, verbatim, plus
/// whether the one-time history backfill already ran. File-backed beside the order
/// store so a future background-refresh target reads it without this process — and
/// so the sign-out wipe is the same identity boundary the wire log observes
/// (review, PR #33): the next token never inherits this account's position.
nonisolated struct SyncStateStore: Sendable {
    struct State: Codable, Hashable, Sendable {
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
        /// A missing key on an older file reads as the same thing an empty
        /// queue does: nothing owed.
        var pendingClaimIDs: [String]? = nil
    }

    private let fileURL: URL

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("claims-sync.json")
    }

    /// The store rooted in the app's shared container — `nil` when it cannot be
    /// resolved (a state the caller renders, never a crash).
    static func inAppGroup(id: String, fileManager: FileManager = .default) -> SyncStateStore? {
        fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: id)
            .map(SyncStateStore.init(directory:))
    }

    /// The stored state, defaulting to *start over*: absent and unreadable both
    /// read as a first sync — a corrupt cursor is not a credential, and replaying
    /// the feed is the recovery, not the failure.
    func read() -> State {
        guard let data = try? Data(contentsOf: fileURL),
              let state = try? JSONDecoder().decode(State.self, from: data)
        else { return State(cursor: nil, historyBackfilled: false) }
        return state
    }

    /// Atomically replaces the file — the cursor and the flag travel together, so a
    /// torn pair (position advanced, backfill forgotten) cannot be observed.
    func write(_ state: State) throws {
        try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
    }

    /// The identity boundary. A wipe that fails leaves a stale cursor — which the
    /// provider answers with `invalid_cursor` and the engine replays anyway, so the
    /// silent `try?` costs a re-sync, not correctness.
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
