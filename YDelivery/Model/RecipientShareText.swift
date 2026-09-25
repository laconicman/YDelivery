import Foundation
import YDeliveryKit

/// Board `5d`'s "one way out": the recipient-facing text — status, the
/// sender's own order number, where it's going and who answers the door, and
/// the provider's ETA while the last stop is still ahead. A text, not a
/// link: the recipient needs no app to read it, and nothing here is private
/// to the sender beyond what the courier will say at the door anyway.
///
/// The ETA follows the callout's own rule (the last stop pending or arrived)
/// rather than a looser one — every surface that speaks the provider's
/// estimate must agree with every other (review, PR #44's words ride too).
nonisolated enum RecipientShareText {
    static func text(for order: Order, orderNumber: String?) -> String {
        var lines: [String] = []
        let status = String(localized: order.status.words)
        lines.append(
            [orderNumber.map { "№\($0)" }, status]
                .compactMap { $0 }
                .joined(separator: " · ")
        )
        if let destination = order.destinationPoint {
            var line = String(localized: "To: \(destination.compactAddress)")
            if let contact = destination.contactSummary {
                line += " — \(contact)"
            }
            lines.append(line)
        }
        if let eta = etaLine(for: order) {
            lines.append(eta)
        }
        return lines.joined(separator: "\n")
    }

    /// «Expected around 19:40» when the provider's clock is aboard, else the
    /// bare minutes — and only while the destination is still ahead (the
    /// callout's own gate), so the text never promises what the card doesn't.
    private static func etaLine(for order: Order) -> String? {
        guard let etaMinutes = order.etaMinutes,
              let destination = order.destinationPoint,
              destination.visit?.status == .pending || destination.visit?.status == .arrived
        else { return nil }
        if let etaAt = order.etaAt {
            // A promise already past is worse than none — the recipient reads
            // this text later, so a stale clock reads as the app lying
            // (review, PR #46). Bare minutes carry no stamp to contradict.
            guard etaAt > .now else { return nil }
            return String(localized:
                "Expected around \(etaAt.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Expected in ~\(etaMinutes) min")
    }
}
