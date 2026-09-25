import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// Board `5a`'s dismissal rules, held still for the tests: searching and
/// active update; delivered ends itself after a linger; every state parked on
/// the sender's decision stays until tapped; a draft never gets a card.
@Suite("Live Activity disposition")
struct LiveActivityDispositionTests {
    typealias Disposition = LiveActivityController.Disposition

    @Test("Live statuses keep the card updating")
    func liveUpdates() {
        for status in [OrderStatus.searching, .active] {
            #expect(Disposition(status: status, hasClaim: true) == .updating)
        }
    }

    @Test("Delivered is the one ending that dismisses itself")
    func deliveredLingers() {
        #expect(Disposition(status: .done, hasClaim: true) == .ending(linger: true))
        #expect(LiveActivityController.deliveredLinger == 4 * 60,
                "board `5a`: ~four minutes on the lock screen, then gone")
    }

    @Test("Sender-decision states stay until tapped")
    func decisionsStay() {
        for status in [OrderStatus.attention, .cancelled] {
            #expect(Disposition(status: status, hasClaim: true) == .ending(linger: false))
        }
    }

    @Test("No claim, no card — a draft has no provider existence")
    func claimlessWritesNothing() {
        for status in OrderStatus.allCases {
            #expect(Disposition(status: status, hasClaim: false) == .none)
        }
    }
}
