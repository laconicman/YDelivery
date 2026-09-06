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

    @Test("The due window states the provider's bound: an hour ahead, thirty days out")
    func dueWindowStatesTheBound() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let window = DeliveryOptions.dueWindow(now: now)
        #expect(window.lowerBound == now.addingTimeInterval(3600))
        #expect(window.upperBound == now.addingTimeInterval(30 * 24 * 3600))
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
