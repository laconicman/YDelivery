import Foundation
import Testing
@testable import YDelivery

/// The picker's network seams are injected, so every transition here runs offline.
@Suite("Point picker")
@MainActor
struct PointPickerModelTests {
    @Test("A dropped pin appears immediately and gains its address asynchronously")
    func dropPinResolves() async throws {
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in "Москва, Красная площадь, 1" },
            searchPlace: { _, _ in throw Unexpected() }
        )

        model.dropPin(latitude: 55.7539, longitude: 37.6208)
        #expect(model.pin?.address == "", "the pin lands before the address arrives")
        #expect(model.isResolving)

        try await waitUntil { !model.isResolving }
        #expect(model.pin?.address == "Москва, Красная площадь, 1")
        #expect(model.lookupError == nil)
    }

    @Test("A failed lookup keeps the pin and renders the error")
    func lookupFailureIsRendered() async throws {
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in throw PointPickerView.Model.NoAddressFound() },
            searchPlace: { _, _ in throw Unexpected() }
        )

        model.dropPin(latitude: 55.7539, longitude: 37.6208)
        try await waitUntil { !model.isResolving }

        #expect(model.pin != nil, "the coordinate is still usable; only the address failed")
        #expect(model.lookupErrorText != nil)

        model.pinAddress = "Москва, вручную"
        #expect(model.lookupErrorText == nil, "an edit supersedes the failure it corrects")
    }

    @Test("Selecting a suggestion resolves through the search seam and clears the query")
    func suggestionSelectionSearches() async throws {
        let found = PickedPlace(latitude: 55.7558, longitude: 37.6173, address: "Москва, Тверская, 1")
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in throw Unexpected() },
            searchPlace: { query, _ in
                #expect(query == "Тверская 1, Москва")
                return found
            }
        )

        model.select(.init(title: "Тверская 1", subtitle: "Москва"))
        try await waitUntil { !model.isResolving }

        #expect(model.pin == found)
        #expect(model.searchText.isEmpty)
    }

    @Test("A newer lookup cancels the stale one rather than racing it")
    func staleLookupIsCancelled() async throws {
        let model = PointPickerView.Model(
            resolveAddress: { latitude, _ in
                if latitude == 1 {
                    // The slow, stale lookup: parked until after cancellation.
                    try await Task.sleep(for: .seconds(2))
                }
                return "Faster"
            },
            searchPlace: { _, _ in throw Unexpected() }
        )

        model.dropPin(latitude: 1, longitude: 1)
        model.dropPin(latitude: 2, longitude: 2)
        try await waitUntil { !model.isResolving }

        #expect(model.pin?.latitude == 2)
        #expect(model.pin?.address == "Faster")
    }

    @Test("A superseded lookup does not switch the spinner off under its replacement")
    func supersededLookupKeepsResolvingFlag() async throws {
        let model = PointPickerView.Model(
            resolveAddress: { latitude, _ in
                // The stale lookup parks far longer than the live one so its cancelled
                // unwind happens while the live one is still in flight.
                try await Task.sleep(for: latitude == 1 ? .seconds(5) : .milliseconds(300))
                return "Resolved"
            },
            searchPlace: { _, _ in throw Unexpected() }
        )

        model.dropPin(latitude: 1, longitude: 1)
        model.dropPin(latitude: 2, longitude: 2)

        // Give the cancelled task's unwind (its sleep throws immediately) time to run its
        // defer — with the regression, this is the moment the spinner wrongly vanished and
        // Confirm enabled against an empty address.
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.isResolving, "only the live lookup may declare resolution over")

        try await waitUntil { !model.isResolving }
        #expect(model.pin?.address == "Resolved")
    }

    @Test("Typing an address during resolution takes it over from the geocoder")
    func addressEditCancelsInFlightLookup() async throws {
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in
                try await Task.sleep(for: .seconds(5))
                return "Слишком поздно"
            },
            searchPlace: { _, _ in throw Unexpected() }
        )

        model.dropPin(latitude: 1, longitude: 1)
        model.pinAddress = "Мой адрес точнее"

        #expect(!model.isResolving, "the user took the address over")
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.pin?.address == "Мой адрес точнее", "the late lookup must not overwrite the edit")
    }

    @Test("The editable address writes through to the pin")
    func addressEditsWriteThrough() {
        let model = PointPickerView.Model(
            initialPlace: PickedPlace(latitude: 1, longitude: 2, address: "Черновик"),
            resolveAddress: { _, _ in throw Unexpected() },
            searchPlace: { _, _ in throw Unexpected() }
        )

        model.pinAddress = "Черновик, подъезд 2"
        #expect(model.pin?.address == "Черновик, подъезд 2")
    }

    @Test("Suggestion identity derives from the datum, not from creation order")
    func suggestionIdentityIsStable() {
        let first = PointPickerView.Model.AddressSuggestion(title: "Арбат 10", subtitle: "Москва")
        let rebuilt = PointPickerView.Model.AddressSuggestion(title: "Арбат 10", subtitle: "Москва")
        #expect(first.id == rebuilt.id)
    }

    private struct Unexpected: Error {}

    /// Polls a main-actor condition briefly; the seams above resolve in microseconds, so
    /// the loop exists only to yield to the model's internal task.
    private func waitUntil(
        _ condition: () -> Bool,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else {
                throw TimedOut()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct TimedOut: Error {}
}
