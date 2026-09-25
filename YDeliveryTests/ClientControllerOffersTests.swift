import Foundation
import OpenAPIRuntime
import Testing
import YandexDeliveryExpressAPI
@testable import YDelivery

/// The two mappings around the offers call — the only place generated types may appear
/// beside app models (CLAUDE.md rule 1).
@Suite("Offers mapping")
@MainActor
struct ClientControllerOffersTests {
    private func request(_ waypoints: [OfferRequest.RequestWaypoint]) -> OfferRequest {
        OfferRequest(waypoints: waypoints, items: [], options: DeliveryOptions())
    }

    @Test("Coordinates go lon,lat on the wire — the trap that answers plausibly, not loudly")
    func coordinatesAreLonLatOnTheWire() {
        let request = ClientController.offersRequest(for: request([
            .init(pointID: UUID(), latitude: 55.646068, longitude: 37.668176, address: "Москва, ул Москворечье, 6"),
            .init(pointID: UUID(), latitude: 55.652212, longitude: 37.648210, address: "Москва, Каширское шоссе, 52"),
        ]))

        #expect(request.routePoints[0].coordinates == [37.668176, 55.646068],
                "longitude first (handoff §4) — a swap pins the Barents Sea, silently")
        #expect(request.routePoints[1].coordinates == [37.648210, 55.652212])
    }

    @Test("Point ids are one-based visit order, and the courier-readable address rides along")
    func requestCarriesOrderAndAddresses() {
        let request = ClientController.offersRequest(for: request([
            .init(pointID: UUID(), latitude: 1, longitude: 2, address: "Первый"),
            .init(pointID: UUID(), latitude: 3, longitude: 4, address: "Второй"),
            .init(pointID: UUID(), latitude: 5, longitude: 6, address: "Третий"),
        ]))

        #expect(request.routePoints.map(\.id) == [1, 2, 3])
        #expect(request.routePoints.map(\.fullname) == ["Первый", "Второй", "Третий"])
    }

    @Test("A scheduled pickup is priced as scheduled, not as immediate")
    func scheduledPickupReachesPricing() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        var options = DeliveryOptions()
        options.due = due
        let wire = ClientController.offersRequest(for: OfferRequest(
            waypoints: [
                .init(pointID: UUID(), latitude: 1, longitude: 2, address: "А"),
                .init(pointID: UUID(), latitude: 3, longitude: 4, address: "Б"),
            ],
            items: [],
            options: options
        ))

        #expect(wire.requirements?.due == due,
                "the provider searches for the time asked; quoting it as now prices another job")
    }

    @Test("A due on its own keeps the requirements container it is the only member of")
    func dueOnlyKeepsItsContainer() {
        var options = DeliveryOptions()
        options.due = Date(timeIntervalSince1970: 1_800_000_000)
        let scheduled = ClientController.offersRequest(for: OfferRequest(
            waypoints: [
                .init(pointID: UUID(), latitude: 1, longitude: 2, address: "А"),
                .init(pointID: UUID(), latitude: 3, longitude: 4, address: "Б"),
            ],
            items: [],
            options: options
        ))
        #expect(scheduled.requirements != nil)

        let immediate = ClientController.offersRequest(for: request([
            .init(pointID: UUID(), latitude: 1, longitude: 2, address: "А"),
            .init(pointID: UUID(), latitude: 3, longitude: 4, address: "Б"),
        ]))
        #expect(immediate.requirements == nil,
                "all-default options still send no container at all")
    }

    @Test("A wire offer reads into the app's vocabulary; the with-VAT total is the price")
    func offerMapsToAppVocabulary() throws {
        let offer = try #require(Offer(Components.Schemas.CalculatedOffer(
            deliveryInterval: .init(
                from: Date(timeIntervalSince1970: 1000),
                to: Date(timeIntervalSince1970: 5000)
            ),
            payload: "offer-token",
            pickupInterval: .init(
                from: Date(timeIntervalSince1970: 500),
                to: Date(timeIntervalSince1970: 900)
            ),
            price: .init(currency: .rub, surgeRatio: 1.1, totalPrice: "1449", totalPriceWithVat: "1767.78"),
            taxiClass: .express
        )))

        #expect(offer.tariff == .express)
        #expect(offer.price == Decimal(string: "1767.78", locale: Locale(identifier: "en_US_POSIX")))
        #expect(offer.currency == "RUB")
        #expect(offer.payload == "offer-token")
        #expect(offer.pickupInterval?.lowerBound == Date(timeIntervalSince1970: 500))
    }

    @Test("An unknown class stays visible by its wire name rather than being dropped")
    func unknownClassStaysVisible() {
        #expect(TariffClass(.sddLong) == .other("sdd_long"))
        #expect(TariffClass.other("sdd_long").words == "sdd_long")
    }

    @Test("An unmarked item's journey ends at the last drop-off, not the return leg")
    func returnLegNeverAnswersAJourney() {
        let request = ClientController.offersRequest(for: OfferRequest(
            waypoints: [
                .init(pointID: UUID(), latitude: 1, longitude: 2, address: "А", role: .pickup),
                .init(pointID: UUID(), latitude: 3, longitude: 4, address: "Б", role: .dropoff),
                .init(pointID: UUID(), latitude: 1, longitude: 2, address: "А", role: .return),
            ],
            items: [],
            options: DeliveryOptions()
        ))

        #expect(request.items.first?.dropoffPoint == 2,
                "point 3 is the courier's way back — the parcel leaves at the door")
    }

    @Test("A backwards interval becomes absence, not a trapping range")
    func backwardsIntervalIsAbsent() throws {
        let offer = try #require(Offer(Components.Schemas.CalculatedOffer(
            deliveryInterval: .init(
                from: Date(timeIntervalSince1970: 5000),
                to: Date(timeIntervalSince1970: 1000)
            ),
            payload: "offer-token",
            pickupInterval: .init(
                from: Date(timeIntervalSince1970: 500),
                to: Date(timeIntervalSince1970: 900)
            ),
            price: .init(currency: .rub, surgeRatio: 1, totalPrice: "10", totalPriceWithVat: "12"),
            taxiClass: .courier
        )))
        #expect(offer.deliveryInterval == nil)
    }

    @Test("A documented refusal keeps the provider's message — the accessor would bury it")
    func refusalKeepsTheProvidersWords() {
        let refusal = Operations.CalculateOffers.Output.badRequest(
            .init(body: .json(.init(code: "400", message: "missing required field 'items'")))
        )
        #expect(throws: ProviderRefusal.self) {
            _ = try ClientController.offers(from: refusal)
        }
        do {
            _ = try ClientController.offers(from: refusal)
            Issue.record("a refusal must throw")
        } catch let error as ProviderRefusal {
            #expect(error.errorDescription == "missing required field 'items'",
                    "the strip's sentence is the wire's message, not an accessor error")
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("An undocumented status keeps its code when no message arrived")
    func undocumentedKeepsTheCode() {
        let output = Operations.CalculateOffers.Output.undocumented(
            statusCode: 418,
            .init()
        )
        do {
            _ = try ClientController.offers(from: output)
            Issue.record("an undocumented status must throw")
        } catch let error as ProviderRefusal {
            #expect(error.status == 418)
        } catch {
            Issue.record("expected ProviderRefusal, got \(error)")
        }
    }

    @Test("Signed out throws the invitation, not an error")
    func signedOutThrowsUnavailable() async {
        let controller = ClientController(tokenStore: TokenStore(service: "test.offers.\(UUID())"))
        await #expect(throws: OffersUnavailable.self) {
            _ = try await controller.offers(for: request([
                .init(pointID: UUID(), latitude: 1, longitude: 2, address: "А"),
                .init(pointID: UUID(), latitude: 3, longitude: 4, address: "Б"),
            ]))
        }
    }
}
