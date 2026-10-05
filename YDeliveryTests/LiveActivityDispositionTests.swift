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

    @Test("A quiet card is re-armed by a healthy sync, never left to flag")
    func quietCardIsRearmed() {
        let window = LiveActivityController.staleAfter
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let state = DeliveryActivityAttributes.ContentState(
            status: .active, orderNumber: "4417", destinationAddress: "Каширское шоссе, 52",
            courierName: nil, courierVehicle: nil, providerStatus: "pickuped",
            etaAt: nil, providerObservedAt: now.addingTimeInterval(-45 * 60),
            destinationPhone: nil)
        // Freshly armed: nothing moved, nothing to send — whatever the age of
        // the provider's own stamp (review: it moves only on a claim change).
        #expect(!LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: now.addingTimeInterval(window), state: state, now: now))
        // Past half its window, the same state is re-sent to push the date on.
        #expect(LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: now.addingTimeInterval(window / 2 - 1),
            state: state, now: now))
        // A card started before stale dates existed is armed on first sight.
        #expect(LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: nil, state: state, now: now))
        // A moved state always goes out.
        var moved = state
        moved.providerStatus = "delivery_arrived"
        #expect(LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: now.addingTimeInterval(window), state: moved, now: now))
        #expect(LiveActivityController.staleDate(now: now) == now.addingTimeInterval(window))
    }
}
