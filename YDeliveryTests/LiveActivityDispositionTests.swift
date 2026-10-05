import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// Board `5a`'s dismissal rules, held still for the tests: searching and
/// active update; a parked decision updates too — ending it would leave a
/// lingering remnant the recovery duplicates (review, PR #44); delivered ends
/// itself after a linger; cancelled stays until tapped; a draft never gets a
/// card.
@Suite("Live Activity disposition")
struct LiveActivityDispositionTests {
    typealias Disposition = LiveActivityController.Disposition

    @Test("Live statuses keep the card updating")
    func liveUpdates() {
        for status in [OrderStatus.searching, .active] {
            #expect(Disposition(status: status, hasClaim: true) == .updating)
        }
    }

    @Test("A parked decision stays live — recovery must not duplicate the card")
    func attentionUpdates() {
        #expect(Disposition(status: .attention, hasClaim: true) == .updating)
    }

    @Test("Delivered is the one ending that dismisses itself")
    func deliveredLingers() {
        #expect(Disposition(status: .done, hasClaim: true) == .ending(.linger))
        #expect(LiveActivityController.deliveredLinger == 4 * 60,
                "board `5a`: ~four minutes on the lock screen, then gone")
    }

    @Test("Cancelled ends and stays until tapped")
    func cancelledStays() {
        #expect(Disposition(status: .cancelled, hasClaim: true) == .ending(.stayUntilTapped))
    }

    @Test("No claim, no card — a draft has no provider existence")
    func claimlessWritesNothing() {
        for status in OrderStatus.allCases {
            #expect(Disposition(status: status, hasClaim: false) == .none)
        }
    }

    @Test("Shelved ends the card whatever the status — the shelf is out of sight")
    func archivedEnds() {
        // A shelved terminal-attention claim must not keep a Lock Screen card
        // it no longer earns — and it must vanish, not sit until tapped:
        // `.immediate`, for every status, claim or none.
        for status in OrderStatus.allCases {
            #expect(Disposition(status: status, hasClaim: true, isArchived: true)
                    == .ending(.immediate), "\(status) shelved ends now, never updates")
            #expect(Disposition(status: status, hasClaim: false, isArchived: true)
                    == .ending(.immediate))
        }
    }
}
