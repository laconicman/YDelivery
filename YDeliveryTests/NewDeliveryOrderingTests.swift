import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// The one irreversible action's state machine, driven through stub steps — offline,
/// like every seam test here.
@Suite("Ordering")
@MainActor
struct NewDeliveryOrderingTests {
    private func readyDraft() -> NewDeliveryView.Model {
        let model = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })
        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "Офис"), for: model.points[0].id)
        model.setContact(Contact(givenName: "Иван", familyName: "Петров", phone: "+7 912 345-67-89"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.64, longitude: 37.66, address: "Дом"), for: model.points[1].id)
        model.setContact(Contact(givenName: "Анна", phone: "+7 998 765-43-21"), for: model.points[1].id)
        var item = ParcelItem()
        item.name = "Ноутбук"
        item.cost = 60000
        model.setItem(item)
        return model
    }

    private func priced(_ model: NewDeliveryView.Model) async {
        await model.loadOffers { _ in
            [Offer(tariff: .express, price: 1190, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: "offer-1")]
        }
    }

    @Test("Blocked drafts state every bound; a ready draft states none")
    func blockersStateTheBounds() async {
        let empty = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })
        #expect(empty.orderBlockers.count == 4, "route, phones, parcel, class — all missing")

        let model = readyDraft()
        #expect(model.orderBlockers == [String(localized: "Pick a delivery class once prices arrive.")])

        await priced(model)
        #expect(model.orderBlockers.isEmpty)
        #expect(model.orderRequest != nil)
    }

    @Test("Create → watch → accept lands placed, with the order history remembers")
    func happyPathPlaces() async {
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()
        #expect(model.ordering == .queued)

        await model.placeOrder(
            create: { request, requestID in
                #expect(request.offerPayload == "offer-1")
                #expect(requestID == model.orderRequestID)
                return PlacedClaim(id: "claim-1", version: 1, status: .estimating, failureText: nil)
            },
            watch: { id in
                #expect(id == "claim-1")
                return PlacedClaim(id: id, version: 2, status: .readyToAccept, failureText: nil)
            },
            accept: { id, version in
                #expect(version == 2)
                return PlacedClaim(id: id, version: version, status: .searching, failureText: nil)
            },
            clock: TestClock()
        )

        #expect(model.ordering == .placed)
        let order = try? #require(model.placedOrder)
        #expect(order?.status == .searching)
        #expect(order?.claimID == "claim-1")
        #expect(order?.price == "1190")
        #expect(order?.tariff == "express")
        #expect(order?.route.first?.contactGivenName == "Иван")
    }

    @Test("A claim already searching is placed, not accepted a second time")
    func alreadyAcceptedIsNotAcceptedAgain() async {
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        var accepts = 0
        await model.placeOrder(
            // The idempotent create hands back the claim an earlier attempt accepted,
            // whose answer was lost on the way home.
            create: { _, _ in PlacedClaim(id: "claim-1", version: 3, status: .searching, failureText: nil) },
            watch: { _ in Issue.record("no watching is needed once it is searching"); return PlacedClaim(id: "claim-1", version: 3, status: .searching, failureText: nil) },
            accept: { id, version in
                accepts += 1
                return PlacedClaim(id: id, version: version, status: .searching, failureText: nil)
            },
            clock: TestClock()
        )

        #expect(accepts == 0, "accepting a dispatched courier's claim again fails every retry")
        #expect(model.ordering == .placed)
        #expect(model.placedOrder?.claimID == "claim-1")
    }

    @Test("A failure during acceptance never claims nothing was charged")
    func uncertainAcceptanceSaysSo() async {
        struct LostAnswer: Error {}
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-1", version: 1, status: .readyToAccept, failureText: nil) },
            watch: { id in PlacedClaim(id: id, version: 1, status: .readyToAccept, failureText: nil) },
            accept: { _, _ in throw LostAnswer() },
            clock: TestClock()
        )

        guard case .unresolved = model.ordering else {
            Issue.record("acceptance began, so the outcome is unknown: \(model.ordering)")
            return
        }
    }

    @Test("A failure before acceptance may still say nothing was charged")
    func failureBeforeAcceptanceIsCertain() async {
        struct Offline: Error {}
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        await model.placeOrder(
            create: { _, _ in throw Offline() },
            watch: { id in PlacedClaim(id: id, version: 1, status: .readyToAccept, failureText: nil) },
            accept: { _, _ in Issue.record("never reached"); return PlacedClaim(id: "x", version: 1, status: .searching, failureText: nil) },
            clock: TestClock()
        )

        guard case .failed = model.ordering else {
            Issue.record("nothing was attempted, so the certainty is honest: \(model.ordering)")
            return
        }
    }

    @Test("A status this app has no rule for is neither accepted nor called placed")
    func unknownStatusIsUnresolved() async {
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        var accepts = 0
        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-1", version: 1, status: .other("cargo_on_hold"), failureText: nil) },
            watch: { id in PlacedClaim(id: id, version: 1, status: .other("cargo_on_hold"), failureText: nil) },
            accept: { id, version in
                accepts += 1
                return PlacedClaim(id: id, version: version, status: .searching, failureText: nil)
            },
            clock: TestClock()
        )

        #expect(accepts == 0, "guessing in either direction is worse than saying so")
        guard case .failed(let reason) = model.ordering else {
            Issue.record("expected a stated failure, got \(model.ordering)")
            return
        }
        #expect(reason.contains("cargo_on_hold"), "the status is named so it can be looked up")
    }

    @Test("An edited retry mints a new token; an unchanged one keeps it")
    func tokenFollowsTheRequest() async {
        struct Offline: Error {}
        let model = readyDraft()
        await priced(model)

        /// Confirm, then fail before acceptance — the only state that may rotate a token.
        func attemptAndFail() async {
            model.confirmOrder()
            await model.placeOrder(
                create: { _, _ in throw Offline() },
                watch: { id in PlacedClaim(id: id, version: 1, status: .readyToAccept, failureText: nil) },
                accept: { id, v in PlacedClaim(id: id, version: v, status: .searching, failureText: nil) },
                clock: TestClock()
            )
        }

        await attemptAndFail()
        let first = model.orderRequestID

        // Order again, unchanged.
        await attemptAndFail()
        #expect(model.orderRequestID == first,
                "the same request must replay, not create a second claim")

        // Now the sender changes the order and presses Order again.
        model.options.proCourier = true
        model.confirmOrder()
        #expect(model.orderRequestID != first,
                "replaying the old claim would send the order they just changed away from")
    }

    @Test("An accept that answers something unexpected is not a placement")
    func acceptIsValidated() async {
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-1", version: 1, status: .readyToAccept, failureText: nil) },
            watch: { id in PlacedClaim(id: id, version: 1, status: .readyToAccept, failureText: nil) },
            // The provider answers, but not with a claim being worked.
            accept: { id, version in PlacedClaim(id: id, version: version, status: .estimating, failureText: nil) },
            clock: TestClock()
        )

        #expect(model.placedOrder == nil, "recording this would claim a delivery that may not exist")
        guard case .unresolved = model.ordering else {
            Issue.record("acceptance was attempted and did not land: \(model.ordering)")
            return
        }
    }

    @Test("Without a confirm, the owned task's appear-run is a no-op")
    func appearRunIsNoOp() async {
        let model = readyDraft()
        await priced(model)

        await model.placeOrder(
            create: { _, _ in
                Issue.record("nothing was confirmed")
                throw Unexpected()
            },
            watch: { _ in throw Unexpected() },
            accept: { _, _ in throw Unexpected() },
            clock: TestClock()
        )
        #expect(model.ordering == .idle)
    }

    @Test("The provider's refusal arrives in its own words")
    func refusalSpeaksTheProvidersWords() async {
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-1", version: 1, status: .estimating, failureText: nil) },
            watch: { _ in
                PlacedClaim(id: "claim-1", version: 1, status: .failed, failureText: "Расстояние слишком велико")
            },
            accept: { _, _ in throw Unexpected() },
            clock: TestClock()
        )
        #expect(model.ordering == .failed("Расстояние слишком велико"))
    }

    @Test("Estimation that never ends becomes an honest timeout, not a spinner")
    func estimationTimesOut() async {
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        var polls = 0
        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-1", version: 1, status: .estimating, failureText: nil) },
            watch: { _ in
                polls += 1
                return PlacedClaim(id: "claim-1", version: 1, status: .estimating, failureText: nil)
            },
            accept: { _, _ in throw Unexpected() },
            clock: TestClock()
        )

        guard case .failed(let reason) = model.ordering else {
            Issue.record("expected the timeout, got \(model.ordering)")
            return
        }
        #expect(reason.contains("too long"))
        #expect(polls > 0, "it did watch before giving up")
    }

    @Test("The idempotency token is minted per draft, not per retry")
    func requestIDIsPerDraft() async {
        let model = readyDraft()
        await priced(model)
        let first = model.orderRequestID

        model.confirmOrder()
        await model.placeOrder(
            create: { _, requestID in
                #expect(requestID == first)
                throw Unexpected()
            },
            watch: { _ in throw Unexpected() },
            accept: { _, _ in throw Unexpected() },
            clock: TestClock()
        )
        if case .failed = model.ordering {} else {
            Issue.record("the failed create should render as failed")
        }

        model.confirmOrder()
        #expect(model.ordering == .queued, "a retry re-queues the same draft")
        #expect(model.orderRequestID == first, "same draft, same token — no second courier")
    }

    private struct Unexpected: Error {}
}

/// Time that only moves when the code under test sleeps — the poll loop runs its sixty
/// virtual seconds in microseconds.
private final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private(set) var current: Duration = .zero

    var now: Instant { Instant(offset: current) }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        current = max(current, deadline.offset)
    }
}
