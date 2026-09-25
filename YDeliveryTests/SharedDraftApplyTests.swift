import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// The share extension's handoff becoming a draft (board `5d`): which end the
/// shared point fills, and whether the saved place that rode along fills the
/// other — the semantics `SharedDraft`'s own tests leave to the consumer.
@Suite("Shared draft becomes a draft")
@MainActor
struct SharedDraftApplyTests {
    private func point(_ address: String,
                       name: String? = nil,
                       phone: String? = nil) -> RoutePoint {
        RoutePoint(
            latitude: 55.65, longitude: 37.64,
            address: address,
            contactName: name, contactPhone: phone)
    }

    @Test("«Это точка доставки» — the shared point lands on the destination")
    func dropoffEnd() {
        let model = NewDeliveryView.Model(sharing: SharedDraft(
            sharedAt: .now,
            point: point("Москва, Каширское шоссе, 52",
                         name: "Анна", phone: "+79987654321"),
            end: .dropoff
        ))
        #expect(model.points.map(\.role) == [.pickup, .dropoff])
        #expect(model.points[0].place == nil, "the pickup stays the sender's to fill")
        #expect(model.points[1].place?.address == "Москва, Каширское шоссе, 52")
        #expect(model.points[1].contact?.phone == "+79987654321")
    }

    @Test("Flipped to the origin, the shared point is the pickup")
    func pickupEnd() {
        let model = NewDeliveryView.Model(sharing: SharedDraft(
            sharedAt: .now,
            point: point("Москва, ул Москворечье, 6"),
            end: .pickup
        ))
        #expect(model.points[0].place?.address == "Москва, ул Москворечье, 6")
        #expect(model.points[1].place == nil, "the destination waits")
    }

    @Test("A saved place aboard fills the end the share left open")
    func otherEndRidesAlong() {
        let model = NewDeliveryView.Model(sharing: SharedDraft(
            sharedAt: .now,
            point: point("Москва, Каширское шоссе, 52"),
            end: .dropoff,
            otherEnd: point("Москва, Тверская, 6", name: "Иван")
        ))
        #expect(model.points[0].place?.address == "Москва, Тверская, 6",
                "the «Откуда» pick resolves without a join — the point came resolved")
        #expect(model.points[0].contact?.fullName == "Иван")
        #expect(model.points[1].place?.address == "Москва, Каширское шоссе, 52")
        #expect(model.isRouteComplete)
    }

    @Test("Door details the text spelled arrive as parts, not prose")
    func doorPartsRide() {
        var door = AddressParts()
        door.entrance = "2"
        door.apartment = "15"
        let model = NewDeliveryView.Model(sharing: SharedDraft(
            sharedAt: .now,
            point: RoutePoint(
                latitude: 55.65, longitude: 37.64,
                address: "Москва, Каширское шоссе, 52",
                addressParts: door),
            end: .dropoff
        ))
        #expect(model.points[1].place?.parts?.entrance == "2")
        #expect(model.points[1].place?.parts?.apartment == "15")
    }
}
