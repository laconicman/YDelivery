import Foundation

/// Which provider words earn a banner, and what the banner says — the pure
/// half of the notification layer (board `5c`: «Push only what needs action;
/// thread per order»). The input is the wire's raw `ClaimStatus` spelling:
/// the collapsed six-state vocabulary can't tell `delivery_arrived` from
/// `performer_found` — both read `.active` — so the mapping happens before
/// the collapse.
///
/// The list is deliberately narrow. A sender needs to act — hand the parcel
/// over, know it arrived, fix what failed — not watch the pipeline, so
/// routine progress (`pickuped`, `returning`, the search states) updates the
/// row silently and the eventual Live Activity owns glanceable progress.
/// Time-sensitive means "interrupt me *now*": a courier waiting at a door,
/// or an ending the sender didn't cause. `delivered` is news, not urgency.
nonisolated enum StatusAnnouncement {
    /// One banner's content — the sentence, whether it ends the order's story
    /// (a terminal banner replaces the thread's earlier entries), and whether
    /// it may break through Focus.
    struct Content: Hashable, Sendable {
        var body: String
        var isTerminal: Bool
        var isTimeSensitive: Bool
    }

    static func content(for providerStatus: String) -> Content? {
        switch providerStatus {
        case "performer_found":
            Content(body: String(localized: "A courier took the order"),
                    isTerminal: false, isTimeSensitive: false)
        case "pickup_arrived":
            Content(body: String(localized: "Courier is at the pickup door"),
                    isTerminal: false, isTimeSensitive: true)
        case "delivery_arrived":
            Content(body: String(localized: "Courier is at the destination door"),
                    isTerminal: false, isTimeSensitive: true)
        case "delivered", "delivered_finish":
            Content(body: String(localized: "Delivered"),
                    isTerminal: true, isTimeSensitive: false)
        case "performer_not_found":
            Content(body: String(localized: "No courier found — the order needs attention"),
                    isTerminal: false, isTimeSensitive: true)
        case "failed":
            Content(body: String(localized: "Delivery failed"),
                    isTerminal: true, isTimeSensitive: true)
        case "cancelled", "cancelled_with_payment", "cancelled_by_taxi",
             "cancelled_with_items_on_hands":
            // A sender-initiated cancel echoes back here too — one expected
            // banner in the thread is the price of also hearing about cancels
            // from other devices and the web cabinet.
            Content(body: String(localized: "The delivery was cancelled"),
                    isTerminal: true, isTimeSensitive: true)
        case "returned", "returned_finish":
            Content(body: String(localized: "The parcel came back"),
                    isTerminal: true, isTimeSensitive: true)
        default:
            nil
        }
    }
}
