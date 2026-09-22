import Foundation
import Testing
@testable import YDelivery

/// The tariff strip's state machine, driven through the fetch the root hands in.
@Suite("Draft offers")
@MainActor
struct NewDeliveryOffersTests {
    private let office = PickedPlace(latitude: 55.7558, longitude: 37.6173, address: "Офис")
    private let home = PickedPlace(latitude: 55.6460, longitude: 37.6681, address: "Дом")

    private func filledDraft() -> NewDeliveryView.Model {
        let model = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })
        model.setPlace(office, for: model.points[0].id)
        model.setPlace(home, for: model.points[1].id)
        // One item feeds every priced test — geo alone prices too (the wire gets a
        // placeholder), but a real parcel keeps these fixtures close to the claim.
        var pricedItem = ParcelItem()
        pricedItem.name = "Коробка"
        pricedItem.cost = 1000
        model.setItem(pricedItem)
        return model
    }

    private func offer(_ id: String, tariff: TariffClass = .courier) -> Offer {
        Offer(tariff: tariff, price: 749, currency: "RUB", pickupInterval: nil, deliveryInterval: nil, payload: id)
    }

    @Test("Prices land and the first offer is selected, so the strip always has an answer")
    func offersLandWithASelection() async {
        let model = filledDraft()
        await model.loadOffers { request in
            #expect(request.waypoints.map(\.address) == ["Офис", "Дом"])
            #expect(request.waypoints.map(\.pointID) == model.points.map(\.id),
                    "items name their stops by these ids")
            return [self.offer("a"), self.offer("b", tariff: .express)]
        }

        #expect(model.offers == .ready([offer("a"), offer("b", tariff: .express)]))
        #expect(model.selectedOfferID == "a")
        #expect(model.selectedOffer?.tariff == .courier)
    }

    @Test("A reload keeps the sender's choice when the same offer returns")
    func reloadKeepsTheChoice() async {
        let model = filledDraft()
        await model.loadOffers { _ in [self.offer("a"), self.offer("b")] }
        model.selectedOfferID = "b"

        await model.loadOffers { _ in [self.offer("b"), self.offer("c")] }
        #expect(model.selectedOfferID == "b", "the same offer returned; the choice stands")

        await model.loadOffers { _ in [self.offer("d")] }
        #expect(model.selectedOfferID == "d", "the choice vanished; the first offer answers")
    }

    @Test("An incomplete route idles the strip and clears the choice")
    func incompleteRouteIdles() async {
        let model = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })
        model.setPlace(office, for: model.points[0].id)

        await model.loadOffers { _ in
            Issue.record("no complete route, no request")
            return []
        }
        #expect(model.offers == .idle)
        #expect(model.selectedOfferID == nil)
    }

    @Test("Signed out is an invitation; failure is a retry — never confused")
    func signedOutAndFailureAreDistinct() async {
        let model = filledDraft()

        await model.loadOffers { _ in throw OffersUnavailable() }
        #expect(model.offers == .signedOut)

        await model.loadOffers { _ in throw ProviderRefusal() }
        guard case .failed(let reason) = model.offers else {
            Issue.record("expected .failed, got \(model.offers)")
            return
        }
        #expect(reason == "no offers today",
                "the strip keeps the provider's own words — a bare refusal is undiagnosable")
    }

    private struct Unexpected: Error {}
    private struct ProviderRefusal: LocalizedError {
        var errorDescription: String? { "no offers today" }
    }
}
extension NewDeliveryOffersTests {
    @Test("Geo alone prices — the parcel refines the quote when it exists")
    func pricingFollowsTheRoute() async {
        let model = NewDeliveryView.Model(estimateRoute: { _ in throw Unexpected() })
        #expect(model.pricingInputs == nil, "an unfinished route is the only precondition")

        model.setPlace(PickedPlace(latitude: 55.75, longitude: 37.61, address: "Офис"), for: model.points[0].id)
        model.setPlace(PickedPlace(latitude: 55.64, longitude: 37.66, address: "Дом"), for: model.points[1].id)
        // Route complete, parcel empty: the request exists; the wire mapping stands
        // a placeholder item in for it — the server demands ≥1 (live, 2026-09-22).
        let bare = model.pricingInputs
        #expect(bare?.items.isEmpty == true)

        var item = ParcelItem()
        item.name = "Ноутбук"
        item.cost = 1000
        model.setItem(item)
        #expect(model.pricingInputs != bare, "the parcel arriving is a different, priced run")
        #expect(model.pricingInputs?.items.count == 1)
    }
}
