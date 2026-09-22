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

    @Test("Describe hands out the contact with an E.164 phone — Save and the bookmark alike")
    func confirmedContactCarriesDialablePhone() {
        let model = PointPickerView.Model(
            initialPlace: PickedPlace(latitude: 55.75, longitude: 37.61, address: "Офис"),
            resolveAddress: { _, _ in throw Unexpected() },
            searchPlace: { _, _ in throw Unexpected() }
        )
        model.contact = Contact(givenName: "Иван", phone: "+7 912 345-67-89", phoneExtension: "12")
        let confirmed = model.confirmedContact
        #expect(confirmed?.phone == "+79123456789", "the claim mapper copies the phone verbatim")
        #expect(confirmed?.givenName == "Иван")
        #expect(confirmed?.phoneExtension == "12")
    }

    @Test("An empty Describe means nobody — nil, not a blank card")
    func emptyContactConfirmsAsNobody() {
        let model = PointPickerView.Model(
            initialPlace: PickedPlace(latitude: 55.75, longitude: 37.61, address: "Офис"),
            resolveAddress: { _, _ in throw Unexpected() },
            searchPlace: { _, _ in throw Unexpected() }
        )
        model.contact = Contact(phoneExtension: "12")
        #expect(model.confirmedContact == nil, "an extension without a phone is noise, not a person")
    }
}
