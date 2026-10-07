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

    @Test("A quiet card is re-armed by a journal check, never by time alone")
    func quietCardIsRearmed() {
        let window = LiveActivityController.staleAfter
        let checked = Date(timeIntervalSince1970: 1_800_000_000)
        let armed = LiveActivityController.staleDate(checkedAt: checked)
        #expect(armed == checked.addingTimeInterval(window))
        let state = DeliveryActivityAttributes.ContentState(
            status: .active, orderNumber: "4417", destinationAddress: "Каширское шоссе, 52",
            courierName: nil, courierVehicle: nil, providerStatus: "pickuped",
            etaAt: nil, providerObservedAt: checked.addingTimeInterval(-45 * 60),
            destinationPhone: nil)
        // Freshly armed by this check: nothing moved, nothing to send — whatever
        // the age of the provider's own stamp (review: it moves only on a claim
        // change). Nor does any later reconcile on the same clock: searches
        // succeeding while the journal fails never move it (review, PR #134).
        #expect(!LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: armed, state: state, checkedAt: checked))
        // A check half a window later re-sends the same state to push the date
        // on; one just short of that waits.
        #expect(LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: armed, state: state,
            checkedAt: checked.addingTimeInterval(window / 2 + 1)))
        #expect(!LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: armed, state: state,
            checkedAt: checked.addingTimeInterval(window / 2 - 1)))
        // A card started before stale dates existed is armed by the first
        // check — and only by a check.
        #expect(LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: nil, state: state, checkedAt: checked))
        #expect(!LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: nil, state: state, checkedAt: nil))
        // A moved state always goes out, check or not.
        var moved = state
        moved.providerStatus = "delivery_arrived"
        #expect(LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: armed, state: moved, checkedAt: checked))
        #expect(LiveActivityController.needsUpdate(
            shown: state, shownStaleDate: armed, state: moved, checkedAt: nil))
    }

    @Test("A card's window comes from the newest read behind it, and never shrinks")
    func windowTakesTheNewestRead() {
        let window = LiveActivityController.staleAfter
        let journal = Date(timeIntervalSince1970: 1_800_000_000)
        let placed = journal.addingTimeInterval(45 * 60)
        // The review's case (PR #134): the journal last succeeded at 10:00,
        // the sender places at 10:45 — placement's own answer dates the card,
        // so it is not born flagged…
        let born = LiveActivityController.staleDate(
            observedAt: placed, checkedAt: journal, shown: nil)
        #expect(born == placed.addingTimeInterval(window))
        // …and an update later in the same outage keeps that window: the
        // 10:00 check cannot unsay the 10:45 answer.
        #expect(LiveActivityController.staleDate(
            observedAt: placed, checkedAt: journal, shown: born) == born)
        // A newer check extends it.
        let later = placed.addingTimeInterval(20 * 60)
        #expect(LiveActivityController.staleDate(
            observedAt: placed, checkedAt: later, shown: born) == later.addingTimeInterval(window))
        // A quiet claim first sighted under a healthy journal rides the
        // journal's window, not its hour-old provider stamp.
        #expect(LiveActivityController.staleDate(
            observedAt: journal.addingTimeInterval(-60 * 60), checkedAt: journal, shown: nil)
                == journal.addingTimeInterval(window))
        // Disk state at launch, no check yet: the card brings its real age.
        let disk = journal.addingTimeInterval(-60 * 60)
        #expect(LiveActivityController.staleDate(
            observedAt: disk, checkedAt: nil, shown: nil) == disk.addingTimeInterval(window))
        // Nothing vouches: no window — a new card opens one at birth, and an
        // unarmed card stays unarmed until a read arrives.
        #expect(LiveActivityController.staleDate(
            observedAt: nil, checkedAt: nil, shown: nil) == nil)
    }
}
