import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

@Suite("Repeat order — board 3e")
@MainActor
struct RepeatDraftTests {
    /// A three-stop order as the store remembers it: positions, contacts, a class —
    /// no roles, no items, no schedule (TechDebt YD-15 is why the route carries none).
    private func rememberedOrder() -> Order {
        Order(
            created: .init(timeIntervalSince1970: 1_800_000_000),
            status: .done,
            route: [
                RoutePoint(
                    latitude: 55.6460, longitude: 37.6681,
                    address: "Москва, ул Москворечье, 6",
                    contactGivenName: "Иван", contactFamilyName: "Петров",
                    contactPhone: "+79123456789"
                ),
                RoutePoint(
                    latitude: 55.7499, longitude: 37.5934,
                    address: "Москва, Тверская, 6",
                    contactName: "Анна Сидорова", contactPhone: "+79987654321"
                ),
                RoutePoint(
                    latitude: 55.7558, longitude: 37.6173,
                    address: "Москва, Арбат, 10"
                ),
            ],
            price: "3400",
            currency: "RUB",
            tariff: "express",
            claimID: "claim-repeat-1"
        )
    }

    @Test("Repeating refills the route with roles by position and contacts at their doors")
    func repeatPrefills() {
        let model = NewDeliveryView.Model(repeating: rememberedOrder())

        #expect(model.points.map(\.role) == [.pickup, .dropoff, .dropoff])
        #expect(model.points.map(\.place?.address) == [
            "Москва, ул Москворечье, 6", "Москва, Тверская, 6", "Москва, Арбат, 10",
        ])
        #expect(model.points[0].contact?.givenName == "Иван")
        #expect(model.points[1].contact?.fullName == "Анна Сидорова")
        #expect(model.points[2].contact == nil)
        #expect(model.isRouteComplete)
    }

    @Test("«Наоборот» runs the route backwards, contacts still answering their own doors")
    func reverseRunsBackwards() {
        let model = NewDeliveryView.Model(repeating: rememberedOrder(), reversed: true)

        #expect(model.points.map(\.role) == [.pickup, .dropoff, .dropoff])
        #expect(model.points.map(\.place?.address) == [
            "Москва, Арбат, 10", "Москва, Тверская, 6", "Москва, ул Москворечье, 6",
        ])
        #expect(model.points[1].contact?.fullName == "Анна Сидорова")
        #expect(model.points[2].contact?.givenName == "Иван")
        #expect(model.isRouteComplete)
    }

    @Test("The order's class is what the strip re-offers when prices land")
    func repeatCarriesTariff() {
        let model = NewDeliveryView.Model(repeating: rememberedOrder())
        #expect(model.chosenTariff == .express)
    }

    @Test("A thin synced claim repeats as a fresh route, not a broken one")
    func thinOrderRepeatsFresh() {
        let thin = Order(
            created: .now, status: .searching,
            route: [RoutePoint(latitude: 55.75, longitude: 37.6, address: "Москва")],
            tariff: "cargo"
        )
        let model = NewDeliveryView.Model(repeating: thin)

        #expect(model.points.map(\.role) == [.pickup, .dropoff])
        #expect(model.points.allSatisfy { $0.place == nil })
        #expect(!model.isRouteComplete)
        #expect(model.chosenTariff == .cargo)
    }

    @Test("Wire spellings round-trip, unknowns keeping their name")
    func tariffWireSpellingRoundTrips() {
        for known in [TariffClass.courier, .express, .cargo, .other("deli")] {
            #expect(TariffClass(wireSpelling: known.wireValue) == known)
        }
        #expect(TariffClass(wireSpelling: "whatever-next") == .other("whatever-next"))
    }

    /// «Заказ 4417» was part of that order — the repeat carries the field values
    /// too, keyed by `fieldRef` so a schema reload matches them to today's labels.
    @Test("Repeating refills the sender's field values")
    func repeatRefillsFields() {
        let order = rememberedOrder()
        let defID = UUID()
        let model = NewDeliveryView.Model(
            repeating: order,
            fields: [OrderCustomField(
                orderID: order.id, fieldRef: defID, name: "Заказ", value: "4417")])

        #expect(model.fieldValues[defID] == "4417")
    }

    /// A field that hides behind «Add field» but carries a value on the repeated
    /// order comes back *visible* — a carried answer must be seen, not sent
    /// invisibly (review, PR #42).
    @Test("A carried answer reveals its hidden field")
    func repeatRevealsAnsweredHiddenField() {
        let order = rememberedOrder()
        let def = CustomFieldDefinition(
            name: "Накладная", isOptional: true, isShownByDefault: false)
        let model = NewDeliveryView.Model(
            repeating: order,
            fields: [OrderCustomField(
                orderID: order.id, fieldRef: def.id, name: def.name, value: "T-12")])
        model.fieldDefinitions = [def]

        #expect(model.visibleFieldDefinitions.map(\.id) == [def.id])
        #expect(model.hiddenFieldDefinitions.isEmpty)
    }

    /// A repeated order can carry a choice the schema has since dropped — the
    /// picker must still show it, or the value rides the request unseen
    /// (review, PR #42). The legacy answer is offered as an extra option rather
    /// than silently cleared: dropping data is never the view's call.
    @Test("A carried answer the schema dropped is still offered")
    func repeatOffersDroppedChoice() {
        let order = rememberedOrder()
        let def = CustomFieldDefinition(
            name: "Тип груза", kind: .choice, choices: ["Коробка"], isOptional: true)
        let model = NewDeliveryView.Model(
            repeating: order,
            fields: [OrderCustomField(
                orderID: order.id, fieldRef: def.id, name: def.name, value: "Документы")])
        model.fieldDefinitions = [def]

        #expect(model.fieldChoices(for: def) == ["Коробка", "Документы"],
                "the historic answer stays visible and selectable")
        #expect(model.fieldValues[def.id] == "Документы")
    }
}
