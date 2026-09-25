import Foundation
import OpenAPIRuntime
import Testing
import YandexDeliveryExpressAPI
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

    /// The callout's parcel line counts the same way the wire write does:
    /// an unassigned item rides the route's ends, quantities sum as pieces.
    @Test("Parcel flow honours the route's ends and counts pieces")
    func parcelFlowCounts() {
        let model = NewDeliveryView.Model()
        let start = model.points[0].id, end = model.points[1].id

        var defaulted = ParcelItem()          // no stops set — rides A→B
        defaulted.name = "Коробка"
        defaulted.quantity = 2
        var middle = ParcelItem()             // explicitly leaves at the start
        middle.name = "Пакет"
        middle.pickupPointID = start
        model.setItem(defaulted)
        model.setItem(middle)

        let flow = model.parcelFlow(at: start)
        #expect(flow.leaving == 3, "two default pieces + the one assigned")
        #expect(flow.arriving == 0)
        #expect(model.parcelFlow(at: end) == (0, 3),
                "both items default their handover to the route's last stop")

        // A third stop joins last — and the route-default rule moves with it.
        let last = model.addStop()
        var routed = middle
        routed.dropoffPointID = end   // the former end, now a middle stop
        model.setItem(routed)
        #expect(model.parcelFlow(at: end).arriving == 1,
                "an assigned handover lands where it names")
        #expect(model.parcelFlow(at: last).arriving == 2,
                "the unassigned item's handover followed the route's end")
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

    @Test("A phone the editor let through half-typed still blocks the order")
    func undialablePhoneBlocks() async {
        let model = readyDraft()
        await priced(model)
        // Saving unfinished contacts is allowed (the editor only hints) — the order
        // gate is where dialability is enforced, with the same rule (review, PR #25).
        model.setContact(Contact(givenName: "Анна", phone: "домофон 12"), for: model.points[1].id)
        #expect(model.orderBlockers == [
            String(localized: "A phone the courier can't dial is no phone yet — finish the number.")
        ])
        #expect(model.orderRequest == nil)

        model.setContact(Contact(givenName: "Анна", phone: "+7 998 765-43-21"), for: model.points[1].id)
        #expect(model.orderBlockers.isEmpty, "a dialable number lifts the block")
    }

    @Test("A dialable number with nobody attached still blocks — the wire wants a name")
    func phoneWithoutNameBlocks() async {
        let model = readyDraft()
        await priced(model)
        // `Contact` on the wire is `name` *and* `phone`, both required (DeepWiki
        // consult on the spec, 2026-09-18) — a nameless phone would 400 at claim.
        model.setContact(Contact(phone: "+7 998 765-43-21"), for: model.points[1].id)
        #expect(model.orderBlockers == [
            String(localized: "The courier calls ahead — every stop needs a person: a name and a phone.")
        ])
        #expect(model.orderRequest == nil)
    }

    /// Board `4b`: a required field the sender hasn't answered blocks the order —
    /// named in the blockers, and the request refuses to assemble without it.
    @Test("A required custom field blocks until filled — and then rides the request")
    func requiredFieldBlocks() async {
        let model = readyDraft()
        await priced(model)
        let field = CustomFieldDefinition(
            name: "Заказ", isOptional: false, carrier: .orderNumber)
        model.fieldDefinitions = [field]

        #expect(model.orderBlockers == [
            String(localized: "«Заказ» is required — the order doesn't leave without it.")
        ])
        #expect(model.orderRequest == nil)

        model.setFieldValue("4417", for: field.id)
        #expect(model.orderBlockers.isEmpty)
        #expect(model.orderRequest?.fieldEntries.first?.value == "4417")
        #expect(model.orderRequest?.fieldEntries.first?.definition.carrier == .orderNumber)
    }

    /// The optional counterpart: an unanswered optional field blocks nothing and
    /// simply doesn't ride — empty is a state, not a value.
    @Test("An optional field unanswered sends nothing")
    func optionalFieldEmpty() async {
        let model = readyDraft()
        await priced(model)
        model.fieldDefinitions = [
            CustomFieldDefinition(name: "Накладная", isOptional: true),
        ]

        #expect(model.orderBlockers.isEmpty)
        #expect(model.orderRequest?.fieldEntries.isEmpty == true)
        #expect(model.customFields(for: UUID()).isEmpty)
    }

    /// «Add field» mechanics: hidden fields stay behind the menu until named in,
    /// and a required one can never hide — the store and editor both enforce it.
    @Test("Hidden fields wait behind Add field; required ones never hide")
    func fieldVisibility() {
        let model = NewDeliveryView.Model()
        let shown = CustomFieldDefinition(name: "Заказ", isShownByDefault: true)
        let hidden = CustomFieldDefinition(name: "Накладная", isShownByDefault: false)
        let required = CustomFieldDefinition(
            name: "Платёж", isOptional: false, isShownByDefault: true)
        model.fieldDefinitions = [shown, hidden, required]

        #expect(model.visibleFieldDefinitions.map(\.name) == ["Заказ", "Платёж"])
        #expect(model.hiddenFieldDefinitions.map(\.name) == ["Накладная"])

        model.revealField(hidden.id)
        #expect(model.visibleFieldDefinitions.map(\.name) == ["Заказ", "Накладная", "Платёж"],
                "revealed, it takes its authored place — schema order, not append order")
        #expect(model.hiddenFieldDefinitions.isEmpty)
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

    /// The answers a claim carries are fixed when the provider takes it — a
    /// schema sync landing during estimation (a definition deleted or renamed
    /// on another device) must not rewrite what history records (review, PR #42).
    @Test("Recording keeps what the claim carried, not the schema that arrived later")
    func placedFieldsFreezeAtCreate() async throws {
        let model = readyDraft()
        await priced(model)
        let field = CustomFieldDefinition(name: "Заказ", carrier: .orderNumber)
        model.fieldDefinitions = [field]
        model.setFieldValue("4417", for: field.id)
        model.confirmOrder()

        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-1", version: 1, status: .readyToAccept, failureText: nil) },
            watch: { _ in Issue.record("never estimating"); return PlacedClaim(id: "claim-1", version: 1, status: .readyToAccept, failureText: nil) },
            accept: { id, version in
                // The schema refresh lands mid-run: «Заказ» is gone by the time
                // acceptance returns.
                model.fieldDefinitions = []
                return PlacedClaim(id: id, version: version, status: .searching, failureText: nil)
            },
            clock: TestClock()
        )

        let order = try #require(model.placedOrder)
        let recorded = model.customFields(for: order.id)
        #expect(recorded.count == 1, "the sent answer survives the schema's departure")
        #expect(recorded.first?.name == "Заказ")
        #expect(recorded.first?.value == "4417")
        #expect(recorded.first?.fieldRef == field.id)
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

    @Test("A schedule that lapses while the sheet is open is shown before it is sent")
    func lapseAtConfirmIsNotSilent() async throws {
        let model = readyDraft()
        // Priced *with* the schedule, which then passes while the sheet is being read.
        // The short window is the point: the offer on hand was bought under that pickup.
        model.options.due = Date.now.addingTimeInterval(0.4)
        await model.loadOffers { request in
            #expect(request.options.due != nil, "the quote is for a scheduled pickup")
            return [Offer(tariff: .express, price: 1190, currency: "RUB",
                          pickupInterval: nil, deliveryInterval: nil, payload: "scheduled")]
        }
        #expect(model.selectedOfferID == "scheduled")
        try await Task.sleep(for: .milliseconds(600))

        model.confirmOrder()

        #expect(model.ordering == .idle,
                "the first press must not send an immediate order under a schedule on screen")
        #expect(model.options.due == nil, "and the «When» line now says what will be sent")
        #expect(model.selectedOfferID == nil,
                "that offer was priced for the pickup that just lapsed")
        #expect(model.chosenTariff != nil, "the class they picked is not forgotten with it")
        #expect(model.orderRequest == nil, "so there is nothing to confirm until prices return")

        // Repricing lands, immediate this time.
        await model.loadOffers { request in
            #expect(request.options.due == nil)
            return [Offer(tariff: .express, price: 1190, currency: "RUB",
                          pickupInterval: nil, deliveryInterval: nil, payload: "fresh")]
        }
        model.confirmOrder()
        #expect(model.ordering == .queued, "the second press orders what it now says")
        #expect(model.orderRequest?.offerPayload == "fresh")
    }

    @Test("A schedule already repriced before confirmation keeps its fresh quote")
    func alreadyRepricedIsNotStranded() async {
        let model = readyDraft()
        model.options.due = Date.now.addingTimeInterval(-60) // lapsed

        // The sheet re-rendered after the lapse, so pricing already ran on the effective
        // (immediate) request and the offer on hand is a fresh one.
        await model.loadOffers { request in
            #expect(request.options.due == nil, "pricing already answers to effective()")
            return [Offer(tariff: .express, price: 1190, currency: "RUB",
                          pickupInterval: nil, deliveryInterval: nil, payload: "fresh")]
        }
        #expect(model.selectedOfferID == "fresh")

        model.confirmOrder()

        #expect(model.selectedOfferID == "fresh",
                "clearing this one strands the sender: pricingInputs is unchanged, so nothing refetches")
        #expect(model.options.due == nil)
        // And the second press can actually order, rather than waiting forever.
        model.confirmOrder()
        #expect(model.ordering == .queued)
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

    @Test("An acceptance whose answer was lost can be asked about, and records once known")
    func unresolvedCanBeReconciled() async {
        struct LostAnswer: Error {}
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()

        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-7", version: 1, status: .readyToAccept, failureText: nil) },
            watch: { id in PlacedClaim(id: id, version: 1, status: .readyToAccept, failureText: nil) },
            accept: { _, _ in throw LostAnswer() },
            clock: TestClock()
        )

        guard case .unresolved(_, let claimID) = model.ordering else {
            Issue.record("expected unresolved, got \(model.ordering)")
            return
        }
        #expect(claimID == "claim-7", "without the id there is no way back at all")

        // The provider had in fact accepted it.
        await model.reconcileUnresolved(watch: { id in
            PlacedClaim(id: id, version: 2, status: .searching, failureText: nil)
        })

        #expect(model.ordering == .placed)
        #expect(model.placedOrder?.claimID == "claim-7", "the order that exists, not a new one")
    }

    @Test("Asking again while it is still unknown leaves it unknown")
    func reconcileKeepsUncertainty() async {
        struct LostAnswer: Error {}
        struct StillOffline: Error {}
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()
        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-7", version: 1, status: .readyToAccept, failureText: nil) },
            watch: { id in PlacedClaim(id: id, version: 1, status: .readyToAccept, failureText: nil) },
            accept: { _, _ in throw LostAnswer() },
            clock: TestClock()
        )

        await model.reconcileUnresolved(watch: { _ in throw StillOffline() })

        guard case .unresolved = model.ordering else {
            Issue.record("a failed read must not resolve anything: \(model.ordering)")
            return
        }
        #expect(model.placedOrder == nil)
    }

    @Test("The order carries the schedule the quote was built from")
    func orderMatchesTheQuotedSchedule() async {
        let model = readyDraft()
        model.options.due = Date.now.addingTimeInterval(-3600) // parked past its pickup
        await priced(model)

        let request = try? #require(model.orderRequest)
        #expect(request?.options.due == nil,
                "pricing quoted an immediate run; sending the expired time could not produce it")

        // And what the sender reads before confirming says the same thing. The review
        // sheet showing a lapsed time over an order that departs immediately is the
        // worst place for these to disagree.
        #expect(model.options.effective().whenSummary == DeliveryOptions().whenSummary,
                "the sheet's «When» line is built from the options the order is built from")
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

    // MARK: The money calls' refusal halves (YD-11)

    @Test("A refused create keeps the provider's words")
    func createRefusalKeepsWords() {
        let refusal = Operations.CreateClaim.Output.badRequest(
            .init(body: .json(.init(code: "validation_failed", message: "Тариф недоступен")))
        )
        do {
            _ = try ClientController.createdClaim(from: refusal)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "Тариф недоступен")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("A refused accept keeps the provider's words — 409 is the stale-version case")
    func acceptConflictKeepsWords() {
        let refusal = Operations.AcceptClaim.Output.conflict(
            .init(body: .json(.init(code: "inappropriate_status", message: "Заявка уже подтверждена")))
        )
        do {
            _ = try ClientController.acceptedClaim(from: refusal, version: 3)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "Заявка уже подтверждена")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("An undocumented accept status keeps its code")
    func acceptUndocumentedKeepsCode() {
        let output = Operations.AcceptClaim.Output.undocumented(statusCode: 503, .init())
        do {
            _ = try ClientController.acceptedClaim(from: output, version: 1)
            Issue.record("an undocumented status must throw")
        } catch let error as ProviderRefusal {
            #expect(error.status == 503)
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("A confirmed accept wraps the wire answer under the caller's version")
    func acceptOkWrapsTheAnswer() throws {
        let output = Operations.AcceptClaim.Output.ok(.init(body: .json(.init(
            id: "claim-9",
            skipClientNotify: false,
            status: .accepted,
            userRequestRevision: "r1",
            version: 4
        ))))
        let claim = try ClientController.acceptedClaim(from: output, version: 7)
        #expect(claim.id == "claim-9")
        #expect(claim.status == .searching)
        #expect(claim.version == 7)
    }

    @Test("A provider-failed reconcile lands failed, not an eternal «Check again»")
    func reconcileConvergesOnProviderFailure() async {
        let model = readyDraft()
        await priced(model)
        model.confirmOrder()
        await model.placeOrder(
            create: { _, _ in PlacedClaim(id: "claim-1", version: 1, status: .readyToAccept, failureText: nil) },
            watch: { _ in throw Unexpected() },
            accept: { _, _ in throw Unexpected() },
            clock: TestClock()
        )
        guard case .unresolved = model.ordering else {
            Issue.record("expected unresolved after the lost accept, got \(model.ordering)")
            return
        }

        await model.reconcileUnresolved(watch: { _ in
            PlacedClaim(id: "claim-1", version: 1, status: .failed, failureText: "Оффер истёк")
        })
        #expect(model.ordering == .failed("Оффер истёк"))
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
