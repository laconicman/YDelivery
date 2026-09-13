import Foundation
import Testing
@testable import YDelivery

/// The one-flow point sheet's state machine: Find → map → Describe, and editing
/// re-enters at Describe with the map one Back away (Round 5, #40/#44; author,
/// 2026-09-14 — one navigation stack, never two disjoint sheets).
@Suite("Point picker flow")
@MainActor
struct PointPickerFlowTests {
    private struct Unexpected: Error {}

    @Test("A fresh picker starts at Find; Continue stacks Describe on the map")
    func freshFlowReachesDescribe() {
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in throw Unexpected() },
            searchPlace: { _, _ in throw Unexpected() }
        )
        #expect(!model.isRefining)
        #expect(!model.isDescribing)
        model.dropPin(latitude: 55.75, longitude: 37.61)
        model.continueToDescribe()
        #expect(model.isDescribing)
    }

    @Test("Editing opens on Describe, with the map one Back away")
    func editingOpensOnDescribe() {
        let place = PickedPlace(latitude: 55.75, longitude: 37.61, address: "Офис")
        let contact = Contact(givenName: "Иван", phone: "+79123456789")
        let model = PointPickerView.Model(
            initialPlace: place,
            initialContact: contact,
            resolveAddress: { _, _ in throw Unexpected() },
            searchPlace: { _, _ in throw Unexpected() }
        )
        #expect(model.isRefining, "the map is beneath, Back lands on it")
        #expect(model.isDescribing, "the facts screen leads (decision #44)")
        #expect(model.contact.givenName == "Иван", "the person rides the same flow")
    }
}
