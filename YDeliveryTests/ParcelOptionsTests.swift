import Foundation
import Testing
import YandexDeliveryExpressAPI
import YDeliveryKit
@testable import YDelivery

/// The parcel, the options, and the two silent unit traps of handoff §4.
@Suite("Parcel and options")
@MainActor
struct ParcelOptionsTests {
    private func waypoint(_ id: UUID, address: String) -> OfferRequest.RequestWaypoint {
        OfferRequest.RequestWaypoint(pointID: id, latitude: 55, longitude: 37, address: address)
    }

    @Test("Centimetres in the UI become metres on the wire — pinned, like lon,lat")
    func sizesGoMetricOnTheWire() throws {
        var item = ParcelItem()
        item.name = "Учебники"
        item.size = ParcelItem.Size(lengthCm: 25, widthCm: 18, heightCm: 15)
        item.weightKg = 2

        let request = ClientController.offersRequest(for: OfferRequest(
            waypoints: [waypoint(UUID(), address: "А"), waypoint(UUID(), address: "Б")],
            items: [item],
            options: DeliveryOptions()
        ))

        let size = try #require(request.items?.first?.size)
        #expect(size.length == 0.25)
        #expect(size.width == 0.18)
        #expect(size.height == 0.15)
        #expect(request.items?.first?.weight == 2, "kilograms pass through untouched")
    }

    @Test("An item names its stops by the route's one-based visit order")
    func itemStopsResolveToVisitOrder() throws {
        let first = UUID()
        let middle = UUID()
        let last = UUID()
        var item = ParcelItem()
        item.name = "Между остановками"
        item.pickupPointID = middle
        item.dropoffPointID = last

        var defaulted = ParcelItem()
        defaulted.name = "От А до Б"

        let request = ClientController.offersRequest(for: OfferRequest(
            waypoints: [
                waypoint(first, address: "А"),
                waypoint(middle, address: "Между"),
                waypoint(last, address: "Б"),
            ],
            items: [item, defaulted],
            options: DeliveryOptions()
        ))

        let items = try #require(request.items)
        #expect(items[0].pickupPoint == 2)
        #expect(items[0].dropoffPoint == 3)
        #expect(items[1].pickupPoint == 1, "nil reads as the route's start")
        #expect(items[1].dropoffPoint == 3, "nil reads as the route's end")
    }

    @Test("Deleting a stop an item named releases the reference rather than rerouting it")
    func deletingAStopReleasesItemReferences() {
        let model = NewDeliveryView.Model()
        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.64, longitude: 37.66, address: "Б"), for: model.points[1].id)
        let middle = model.addStop()
        model.setPlace(PickedPlace(latitude: 55.70, longitude: 37.63, address: "Между"), for: middle)

        var item = ParcelItem()
        item.name = "Коробка"
        item.dropoffPointID = middle
        model.setItem(item)

        // The stop the item was going to leave at goes away.
        let index = model.points.firstIndex { $0.id == middle }!
        model.removePoints(at: IndexSet(integer: index))

        #expect(model.items[0].dropoffPointID == nil,
                "a reference to nothing would read downstream as 'no preference' and move the box")
    }

    @Test("A request cannot carry an item stop it has no waypoint for")
    func requestNormalisesDanglingItemStops() throws {
        let first = UUID()
        let last = UUID()
        var item = ParcelItem()
        item.name = "Коробка"
        item.dropoffPointID = UUID() // a stop that is not in this route

        let request = OfferRequest(
            waypoints: [waypoint(first, address: "А"), waypoint(last, address: "Б")],
            items: [item],
            options: DeliveryOptions()
        )

        #expect(request.items[0].dropoffPointID == nil,
                "the boundary type makes the ambiguous state unrepresentable")
        let wire = ClientController.offersRequest(for: request)
        #expect(try #require(wire.items)[0].dropoffPoint == 2, "and nil means the ends, unambiguously")
    }

    @Test("Scheduling on writes a time; scheduling off takes it away")
    func schedulingWritesItsTime() {
        let window = DeliveryOptions.dueWindow(for: .express, now: Date(timeIntervalSince1970: 1_800_000_000))
        var options = DeliveryOptions()

        options.setScheduled(true, within: window)
        #expect(options.due == window.lowerBound,
                "saving straight after the toggle must not depart as an immediate delivery")

        let chosen = window.lowerBound.addingTimeInterval(7200)
        options.due = chosen
        options.setScheduled(true, within: window)
        #expect(options.due == chosen, "a time already chosen is not overwritten")

        options.setScheduled(false, within: window)
        #expect(options.due == nil)
    }

    @Test("The courier's note is carried, but it does not re-price the route")
    func theNoteDoesNotReprice() {
        let model = NewDeliveryView.Model()
        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.64, longitude: 37.66, address: "Б"), for: model.points[1].id)

        let before = model.pricingInputs
        model.options.comment = "Позвоните за 10 минут"
        #expect(model.pricingInputs == before,
                "the offers request has nowhere to put it, so every keystroke refetched the same prices")
        #expect(model.options.comment == "Позвоните за 10 минут", "it still rides to claim creation")
    }

    @Test("The explainer names what a class cannot take — the promise the item row keeps too")
    func explainerNamesWhatDoesNotFit() {
        var big = ParcelItem()
        big.name = "Комплект учебников"
        big.weightKg = 400

        let card = NewDeliveryView.TariffExplainer.Card(tariff: .courier, offer: nil, misfits: [big])
        let misfit = card.misfit ?? ""
        #expect(misfit.contains("Комплект учебников"),
                "naming the box beats counting it — the sender knows which one to reconsider")

        let fine = NewDeliveryView.TariffExplainer.Card(tariff: .cargo, offer: nil, misfits: [])
        #expect(fine.misfit == nil)
    }

    @Test("Only departures from the defaults go on the wire; all-default sends nothing")
    func requirementsStayHonest() {
        let base = OfferRequest(
            waypoints: [waypoint(UUID(), address: "А"), waypoint(UUID(), address: "Б")],
            items: [],
            options: DeliveryOptions()
        )
        #expect(ClientController.offersRequest(for: base).requirements == nil,
                "door-to-door true and zero loaders are the provider's own defaults")
        #expect(ClientController.offersRequest(for: base).items == nil)

        var loaded = base
        loaded.options.thermobag = true
        loaded.options.loaders = 2
        loaded.options.toDoor = false
        loaded.options.proCourier = true
        let requirements = ClientController.offersRequest(for: loaded).requirements
        #expect(requirements?.cargoLoaders == 2)
        #expect(requirements?.cargoOptions == [.thermobag])
        #expect(requirements?.proCourier == true)
        #expect(requirements?.skipDoorToDoor == true)
    }

    @Test("Switching class renormalizes what is bound to one — §4, enforced in the UI")
    func classChangeRenormalizesOptions() async {
        let model = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })
        model.setPlace(PickedPlace(latitude: 55, longitude: 37, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 56, longitude: 38, address: "Б"), for: model.points[1].id)

        func offer(_ id: String, _ tariff: TariffClass) -> Offer {
            Offer(tariff: tariff, price: 1, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: id)
        }
        await model.loadOffers { _ in [offer("courier", .courier), offer("cargo", .cargo)] }

        model.options.thermobag = true
        model.selectedOfferID = "cargo"
        #expect(!model.options.thermobag, "a thermal bag cannot leave with a van")

        model.options.loaders = 2
        model.selectedOfferID = "courier"
        #expect(model.options.loaders == 0, "loaders ride only in the cargo van")
    }

    @Test("A blank item saves as nothing; an emptied item removes itself")
    func blankItemsVanish() {
        let model = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })

        model.setItem(ParcelItem())
        #expect(model.items.isEmpty, "cancelled or empty — no ghost rows")

        var item = ParcelItem()
        item.name = "Ноутбук"
        model.setItem(item)
        #expect(model.items.count == 1)

        item.name = ""
        model.setItem(item)
        #expect(model.items.isEmpty, "emptying the card is removing the item")
    }

    @Test("Repricing keeps the class the sender chose, not the first one offered")
    func repricingKeepsTheChosenClass() async {
        let model = NewDeliveryView.Model()
        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.64, longitude: 37.66, address: "Б"), for: model.points[1].id)

        func offer(_ payload: String, _ tariff: TariffClass) -> Offer {
            Offer(tariff: tariff, price: 100, currency: "RUB",
                  pickupInterval: nil, deliveryInterval: nil, payload: payload)
        }

        await model.loadOffers { _ in [offer("a1", .courier), offer("b1", .cargo)] }
        model.selectedOfferID = "b1"
        #expect(model.selectedOffer?.tariff == .cargo)

        // Payloads rotate on every recalculation; the class is what was chosen.
        await model.loadOffers { _ in [offer("a2", .courier), offer("b2", .cargo)] }
        #expect(model.selectedOffer?.tariff == .cargo,
                "matching by payload alone moved the sender to the first class silently")
        #expect(model.selectedOfferID == "b2", "and the id is the payload that gets spent")
    }

    @Test("A schedule the window has passed is no schedule")
    func lapsedScheduleReadsAsSoonAsPossible() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var options = DeliveryOptions()
        options.due = now.addingTimeInterval(-3600) // a parked draft outlived its pickup

        #expect(options.scheduleHasLapsed(now: now))
        #expect(options.effective(now: now).due == nil,
                "sending a past date failed every quote until someone reopened the options")

        var live = DeliveryOptions()
        live.due = now.addingTimeInterval(2 * 3600)
        #expect(!live.scheduleHasLapsed(now: now))
        #expect(live.effective(now: now).due == live.due)
    }

    @Test("An item cannot be handed over before, or where, it was collected")
    func itemJourneysStayPossible() {
        let model = NewDeliveryView.Model()
        model.setPlace(PickedPlace(latitude: 1, longitude: 1, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 2, longitude: 2, address: "Б"), for: model.points[1].id)
        let middle = model.addStop()
        model.setPlace(PickedPlace(latitude: 3, longitude: 3, address: "Между"), for: middle)

        var item = ParcelItem()
        item.name = "Коробка"
        item.pickupPointID = model.points[1].id  // visit order 2
        item.dropoffPointID = middle             // visit order 3 — a possible journey
        model.setItem(item)
        #expect(model.items[0].dropoffPointID == middle, "valid on the way in")

        // Reordering drags the handover in front of the pickup.
        model.movePoints(from: IndexSet(integer: 2), to: 1)
        #expect(model.items[0].dropoffPointID == nil,
                "a box handed over before it is collected is a journey the provider refuses")
    }

    @Test("A cargo date days out survives the pricing task's own loading state")
    func cargoScheduleSurvivesRepricing() async {
        let model = NewDeliveryView.Model()
        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.64, longitude: 37.66, address: "Б"), for: model.points[1].id)
        let due = Date.now.addingTimeInterval(3 * 24 * 3600) // legal for a van, not a courier
        model.options.due = due

        // The identity pricing answers to must not change when pricing begins.
        let before = model.pricingInputs
        await model.loadOffers { request in
            #expect(request.options.due == due,
                    "deriving the window from selectedOffer cleared this the moment offers left .ready")
            return [Offer(tariff: .cargo, price: 1, currency: "RUB",
                          pickupInterval: nil, deliveryInterval: nil, payload: "c1")]
        }
        #expect(model.pricingInputs == before, "a changed identity would restart the task in a loop")
    }

    @Test("The chosen class outlives a repricing, so editors opened mid-load are right")
    func chosenTariffSurvivesLoading() async {
        let model = NewDeliveryView.Model()
        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.64, longitude: 37.66, address: "Б"), for: model.points[1].id)

        await model.loadOffers { _ in
            [Offer(tariff: .cargo, price: 1, currency: "RUB",
                   pickupInterval: nil, deliveryInterval: nil, payload: "c1")]
        }
        #expect(model.chosenTariff == .cargo)

        // Mid-reload, `selectedOffer` is nil — the options editor used to read that as
        // "no class" and clamp a multi-day pickup into the four-hour default.
        let due = Date.now.addingTimeInterval(3 * 24 * 3600)
        model.options.due = due
        var seen: TariffClass?
        await model.loadOffers { _ in
            seen = model.chosenTariff
            #expect(model.selectedOffer == nil, "the transient state really is nil here")
            return [Offer(tariff: .cargo, price: 1, currency: "RUB",
                          pickupInterval: nil, deliveryInterval: nil, payload: "c2")]
        }

        #expect(seen == .cargo, "the class the sender chose does not vanish while prices reload")
        #expect(DeliveryOptions.dueWindow(for: seen).contains(due),
                "so a van's multi-day pickup stays inside the window it is judged against")
    }

    @Test("A default endpoint is a position, so it constrains the other end too")
    func defaultEndpointsCannotReverse() {
        let model = NewDeliveryView.Model()
        model.setPlace(PickedPlace(latitude: 1, longitude: 1, address: "А"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 2, longitude: 2, address: "Б"), for: model.points[1].id)
        let middle = model.addStop()
        model.setPlace(PickedPlace(latitude: 3, longitude: 3, address: "Между"), for: middle)
        let first = model.points[0].id

        // Pickup left at its default (the route's start) and the handover named as that
        // same first stop — equal, not merely reversed.
        var item = ParcelItem()
        item.name = "Коробка"
        item.dropoffPointID = first
        model.setItem(item)
        #expect(model.items[0].dropoffPointID == nil,
                "handing over at the door it was collected from is not a journey")

        // Handover left at its default (the route's end) and the pickup named as the end.
        var second = ParcelItem()
        second.name = "Вторая"
        second.pickupPointID = model.points[model.points.count - 1].id
        model.setItem(second)
        let saved = model.items.first { $0.id == second.id }
        #expect(saved?.pickupPointID == nil,
                "collecting at the last stop leaves nowhere to hand it over")
    }

    @Test("A class judges the whole parcel, not one row at a time")
    func parcelWeightIsJudgedTogether() {
        func box(_ kg: Double, quantity: Int = 1) -> ParcelItem {
            var item = ParcelItem()
            item.name = "Коробка"
            item.weightKg = kg
            item.quantity = quantity
            return item
        }

        // Each row passes a courier's 10 kg on its own; together they are 15.
        let rows = [box(5), box(5), box(5)]
        #expect(rows.allSatisfy { TariffClass.courier.fits($0) })
        #expect(!TariffClass.courier.fitsParcel(rows), "ten 5 kg boxes are not a courier job")

        // Quantity counts on one row too.
        #expect(!TariffClass.courier.fits(box(5, quantity: 3)))
        #expect(TariffClass.courier.fits(box(5, quantity: 2)))
    }

    @Test("Too heavy together is said where no single row is at fault")
    func combinedWeightIsExplained() {
        let model = NewDeliveryView.Model()
        for _ in 0..<3 {
            var item = ParcelItem()
            item.name = "Коробка"
            item.weightKg = 5
            model.setItem(item)
        }

        #expect(model.itemsThatDontFit(.courier).isEmpty, "no box is the problem")
        #expect(model.parcelIsTooHeavy(for: .courier))
        let card = NewDeliveryView.TariffExplainer.Card(
            tariff: .courier, offer: nil, misfits: [], parcelIsTooHeavy: true
        )
        #expect(card.misfit?.isEmpty == false, "the card says so rather than showing nothing")
    }

    @Test("Fit judges only what is stated, and lets the box rotate")
    func fitChecksAreHonest() {
        var box = ParcelItem()
        #expect(TariffClass.courier.fits(box), "nothing stated, nothing to refuse")

        box.size = ParcelItem.Size(lengthCm: 50, widthCm: 80, heightCm: 40)
        #expect(TariffClass.courier.fits(box), "80 on any side fits the 80-bound rotated")

        box.size = ParcelItem.Size(lengthCm: 90, widthCm: 40, heightCm: 30)
        #expect(!TariffClass.courier.fits(box))
        #expect(TariffClass.express.fits(box))

        box.size = nil
        box.weightKg = 12
        #expect(!TariffClass.courier.fits(box))
        #expect(TariffClass.express.fits(box))
    }

    @Test("The due window offers only what a class can be asked for")
    func dueWindowStatesTheBound() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // Express: the API document's four-hour ceiling, not the handoff's thirty days.
        // Offering a month and being refused at ordering time is the worse failure.
        let express = DeliveryOptions.dueWindow(for: .express, now: now)
        #expect(express.lowerBound == now.addingTimeInterval(3600))
        #expect(express.upperBound == now.addingTimeInterval(4 * 3600))

        #expect(DeliveryOptions.dueWindow(for: .cargo, now: now).upperBound
            == now.addingTimeInterval(5 * 24 * 3600), "the van may be booked days out")

        #expect(DeliveryOptions.dueWindow(for: nil, now: now).upperBound == express.upperBound,
                "an unknown class gets the tightest ceiling we can justify")
    }

    @Test("Explicit name components survive the store exactly — parsing never enters it")
    func nameComponentsSurviveTheStore() throws {
        let ivan = Contact(givenName: "Иван", familyName: "Петров", phone: "+7 912 345-67-89")
        #expect(ivan.fullName == "Иван Петров", "joined by the formatter, never by hand")
        #expect(ivan.summary.hasPrefix("Иван Петров"))

        // The whole reason components are stored: Foundation's name parser returns nil
        // for Cyrillic (verified 2026-09-06), so a single stored string could never be
        // split back in this app's first market.
        let point = RoutePoint(PickedPlace(latitude: 55, longitude: 37, address: "А"), contact: ivan)
        #expect(point.contactName == "Иван Петров", "the wire still gets its one string")
        #expect(Contact(at: point) == ivan)
    }

    @Test("Legacy single-string rows still yield a contact a courier can ask for")
    func legacyNamesDegradeHonestly() {
        let latin = Contact(fullName: "Ivan Petrov")
        #expect(latin.givenName == "Ivan")
        #expect(latin.familyName == "Petrov")

        // Cyrillic: the parser refuses it, so the name stays whole in the given name —
        // displayable, never dropped.
        let cyrillic = Contact(fullName: "Иван Петров")
        #expect(cyrillic.givenName == "Иван Петров")
        #expect(cyrillic.familyName.isEmpty)
        #expect(cyrillic.fullName == "Иван Петров")
    }

    @Test("The dimensions line is one piece of knowledge, wherever it renders")
    func dimensionsLineHasOneHome() {
        #expect(Dimensions.centimeters([25, 18, 15]).contains(Dimensions.separator))
        #expect(TariffClass.courier.limits.contains(Dimensions.centimeters([80, 50, 50])))
    }

    private struct Unexpected: Error {}
}
