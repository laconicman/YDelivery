import Foundation
import Testing
import YandexDeliveryExpressAPI
import YDeliveryKit
@testable import YDelivery

/// The create-claim mapping — the last place generated types appear, and the one that
/// carries every §4 trap at once.
@Suite("Claims mapping")
@MainActor
struct ClaimsMappingTests {
    private func order() -> OrderRequest {
        let pickupID = UUID()
        let dropoffID = UUID()
        var item = ParcelItem()
        item.name = "Ноутбук"
        item.quantity = 1
        item.cost = Decimal(string: "60000.50", locale: Locale(identifier: "en_US_POSIX"))
        item.currency = "RUB"
        item.weightKg = 1.6
        item.size = ParcelItem.Size(lengthCm: 35, widthCm: 25, heightCm: 5)

        var options = DeliveryOptions()
        options.proCourier = true
        options.toDoor = false
        options.comment = "  Позвонить за час  "

        return OrderRequest(
            points: [
                .init(
                    pointID: pickupID,
                    latitude: 55.646068,
                    longitude: 37.668176,
                    address: "Москва, ул Москворечье, 6",
                    parts: AddressParts(entrance: "А", floor: "3", apartment: "301", intercom: "301#"),
                    contact: Contact(givenName: "Иван", familyName: "Петров", phone: "+7 912 345-67-89", phoneExtension: "12"),
                    role: .pickup
                ),
                .init(
                    pointID: dropoffID,
                    latitude: 55.652212,
                    longitude: 37.648210,
                    address: "Москва, Каширское шоссе, 52",
                    parts: nil,
                    contact: Contact(givenName: "Анна", phone: "+7 998 765-43-21"),
                    role: .return
                ),
            ],
            items: [item],
            options: options,
            offerPayload: "offer-token",
            tariffWireValue: "express"
        )
    }

    @Test("The create request carries every §4 answer at once")
    func createRequestCarriesTheTraps() throws {
        let request = ClientController.createRequest(for: order())

        let first = try #require(request.routePoints.first)
        #expect(first.address.coordinates == [37.668176, 55.646068], "lon,lat — always")
        #expect(first.address.porch == "А")
        #expect(first.address.sfloor == "3")
        #expect(first.address.sflat == "301")
        #expect(first.address.doorCode == "301#")
        #expect(first.contact.name == "Иван Петров", "components joined by the formatter")
        #expect(first.contact.phoneAdditionalCode == "12", "the extension has its own wire field")
        #expect(first._type == .source)
        #expect(first.visitOrder == 1)

        let last = try #require(request.routePoints.last)
        #expect(last._type == ._return)
        #expect(last.address.porch == nil, "absence stays absent, not empty strings")

        let item = try #require(request.items.first)
        #expect(item.costValue == "60000.5", "POSIX decimal string — never a locale comma")
        #expect(item.size?.length == 0.35)
        #expect(item.pickupPoint == 1)
        #expect(item.dropoffPoint == 2)

        #expect(request.clientRequirements?.taxiClass == .express)
        #expect(request.clientRequirements?.proCourier == true)
        #expect(request.skipDoorToDoor == true)
        #expect(request.comment == "Позвонить за час", "trimmed for the wire")
        #expect(request.offerPayload == "offer-token")
    }

    @Test("The wire's status zoo collapses to what the flow decides on")
    func statusZooCollapses() {
        #expect(PlacedClaim.Progress(.new) == .estimating)
        #expect(PlacedClaim.Progress(.estimating) == .estimating)
        #expect(PlacedClaim.Progress(.readyForApproval) == .readyToAccept)
        #expect(PlacedClaim.Progress(.estimatingFailed) == .failed)
        #expect(PlacedClaim.Progress(.accepted) == .searching)
        #expect(PlacedClaim.Progress(.performerLookup) == .searching)
        #expect(PlacedClaim.Progress(.pickuped) == .other("pickuped"),
                "past the draft's job, polling reports honestly rather than guessing")
    }

    @Test("Money on the wire never wears the locale's comma")
    func wireDecimalIsPOSIX() {
        #expect(ClientController.wireDecimal(Decimal(string: "1190", locale: Locale(identifier: "en_US_POSIX"))!) == "1190")
        #expect(ClientController.wireDecimal(Decimal(string: "60000.50", locale: Locale(identifier: "en_US_POSIX"))!) == "60000.5")
        #expect(!ClientController.wireDecimal(Decimal(string: "2500.25", locale: Locale(identifier: "en_US_POSIX"))!).contains(","))
    }
}
