import Foundation
import MapKit
import Testing
import YDeliveryKit
@testable import YDelivery

/// The paste and location flows, driven through the injected seams — every transition
/// runs offline and lands in a rendered state, never a guess.
@Suite("Point picker paste and location")
@MainActor
struct PointPickerPasteLocationTests {
    private func model(
        resolve: @escaping PointPickerView.Model.AddressResolver = { _, _ in "Resolved" },
        expand: @escaping PointPickerView.Model.LinkExpander = { _ in throw Unexpected() },
        locate: @escaping PointPickerView.Model.LocationFix = { throw Unexpected() }
    ) -> PointPickerView.Model {
        PointPickerView.Model(
            resolveAddress: resolve,
            searchPlace: { _, _ in throw Unexpected() },
            expandLink: expand,
            locateOnce: locate
        )
    }

    @Test("A point link previews with a resolved name before it may join the route")
    func pointLinkPreviews() async throws {
        let model = model(resolve: { _, _ in "Москва, Красная площадь, 1" })

        model.paste("https://yandex.ru/maps/?pt=37.62094,55.75361")
        try await waitUntil { model.pasteState != .resolving }

        guard case .preview(let place, let source) = model.pasteState else {
            Issue.record("expected a preview, got \(String(describing: model.pasteState))")
            return
        }
        #expect(place.address == "Москва, Красная площадь, 1")
        #expect(place.latitude == 55.75361)
        #expect(source == .yandexMaps)
    }

    @Test("Placing the previewed point moves it to the map — the one Done")
    func previewedPointRefines() async throws {
        let model = model()
        model.paste("geo:55.7558,37.6173")
        try await waitUntil { model.pasteState != .resolving }

        model.placePreviewedPoint()
        #expect(model.pin?.latitude == 55.7558)
        #expect(model.isRefining)
        #expect(model.pasteState == nil)
    }

    @Test("A route link resolves both ends and offers them together")
    func routeLinkPreviewsBothEnds() async throws {
        let model = model(resolve: { latitude, _ in "Адрес \(latitude)" })

        model.paste("https://yandex.ru/maps/?rtext=59.967870,30.242658~59.898495,30.299559")
        try await waitUntil { model.pasteState != .resolving }

        let route = try #require(model.previewedRoute)
        #expect(route.from.latitude == 59.967870)
        #expect(route.to.latitude == 59.898495)
        #expect(route.from.address == "Адрес 59.96787")
    }

    @Test("A short link expands once, then follows the grammar of what it became")
    func shortLinkExpands() async throws {
        let model = model(
            resolve: { _, _ in "Москва, Тверская, 1" },
            expand: { url in
                #expect(url.absoluteString == "https://maps.app.goo.gl/Abc123")
                return URL(string: "https://www.google.com/maps?q=55.7558,37.6173")!
            }
        )

        model.paste("https://maps.app.goo.gl/Abc123")
        try await waitUntil {
            if case .preview = model.pasteState { true } else { false }
        }

        guard case .preview(let place, let source) = model.pasteState else { return }
        #expect(place.latitude == 55.7558)
        #expect(source == .googleMaps)
    }

    @Test("A short link that cannot expand fails with the original kept visible")
    func shortLinkOfflineKeepsTheOriginal() async throws {
        let model = model(expand: { _ in throw URLError(.notConnectedToInternet) })

        model.paste("https://go.2gis.com/7muvw")
        try await waitUntil { model.pasteState != .expanding }

        #expect(model.pasteState == .failed(
            .couldNotExpand(original: URL(string: "https://go.2gis.com/7muvw")!)
        ))
    }

    @Test("An org card declines honestly; prose is not offered at all")
    func declinesAreHonest() {
        let model = model()

        model.paste("https://yandex.ru/maps/org/1184371713")
        #expect(model.pasteState == .failed(.noCoordinates))

        model.paste("просто текст, не ссылка")
        #expect(model.pasteState == .failed(.notALink))
    }

    @Test("A location fix drops the pin on the map; a coarse fix says it is approximate")
    func locationFixRefines() async throws {
        let model = model(
            resolve: { _, _ in "Москва, где-то рядом" },
            locate: { (55.7558, 37.6173, 1200) }
        )

        model.continueAfterLocationPrompt()
        try await waitUntil { !model.isLocating && !model.isResolving }

        #expect(model.pin?.latitude == 55.7558)
        #expect(model.isRefining)
        #expect(model.locationIsApproximate, "a kilometre-wide fix cannot name a door")
    }

    @Test("A choice the sender makes retires a location fix still in flight")
    func lateFixDoesNotOverwriteANewerChoice() async throws {
        let released = AsyncStream<Void>.makeStream()
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in "Resolved" },
            searchPlace: { _, _ in PickedPlace(latitude: 55.64, longitude: 37.66, address: "Каширское шоссе, 52") },
            expandLink: { _ in throw Unexpected() },
            locateOnce: {
                // Still looking when the sender gives up and searches instead.
                var iterator = released.stream.makeAsyncIterator()
                _ = await iterator.next()
                return (55.7558, 37.6173, 40)
            }
        )

        model.continueAfterLocationPrompt()
        model.searchAsAddress("Каширское шоссе 52")
        try await waitUntil { !model.isResolving }
        #expect(model.pin?.address == "Каширское шоссе, 52")

        released.continuation.yield()
        released.continuation.finish()
        try await Task.sleep(for: .milliseconds(50))

        #expect(model.pin?.address == "Каширское шоссе, 52",
                "the fix the sender stopped waiting for must not drop a pin over their choice")
        #expect(!model.isLocating)
    }

    @Test("Denied location is a rendered state, not an error")
    func deniedLocationRenders() async throws {
        let model = model(locate: { throw PointPickerView.Model.LocationDenied() })

        model.continueAfterLocationPrompt()
        try await waitUntil { !model.isLocating }

        #expect(model.locationDenied)
        #expect(model.lookupError == nil)
        #expect(!model.isRefining, "nothing was placed, so there is nothing to refine")
    }

    @Test("The Settings start city becomes the empty map's start and biases the search")
    func startCityResolves() async {
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in throw Unexpected() },
            searchPlace: { query, _ in
                #expect(query == "Санкт-Петербург")
                return PickedPlace(latitude: 59.93, longitude: 30.31, address: "Санкт-Петербург")
            },
            expandLink: { _ in throw Unexpected() },
            locateOnce: { throw Unexpected() }
        )

        await model.resolveStartCity("Санкт-Петербург")
        #expect(model.startRegion?.center.latitude == 59.93)
        #expect(model.visibleRegion?.center.latitude == 59.93, "searches lean toward the market")

        await model.resolveStartCity("  ")
        #expect(model.startRegion == nil, "clearing the setting clears the fallback")
    }

    @Test("A start city that lands after the map opened still publishes its region")
    func startCityArrivesLate() async {
        let model = PointPickerView.Model(
            resolveAddress: { _, _ in "Resolved" },
            searchPlace: { _, _ in PickedPlace(latitude: 59.93, longitude: 30.31, address: "Санкт-Петербург") },
            expandLink: { _ in throw Unexpected() },
            locateOnce: { throw Unexpected() }
        )
        // The refine map opened first and reported where it landed: the built-in anchor,
        // which is a default nobody chose rather than a place the sender navigated to.
        model.visibleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )

        await model.resolveStartCity("Санкт-Петербург")

        #expect(model.startRegion?.center.latitude == 59.93,
                "an empty, undriven map watches this and follows it (review, PR #19)")
    }

    @Test("A wrong start city keeps the built-in fallback silently")
    func startCityFailureIsSilent() async {
        let model = model()
        await model.resolveStartCity("Кудыкина гора")
        #expect(model.startRegion == nil)
        #expect(model.lookupError == nil, "a Settings typo must not block picking")
    }

    @Test("The confirmed place carries its parts; empty parts stay absent")
    func confirmedPlaceCarriesParts() {
        let model = model()
        model.dropPin(latitude: 55.75, longitude: 37.61)
        #expect(model.confirmedPlace?.parts == nil)

        model.addressParts.entrance = "А"
        model.addressParts.apartment = "301"
        #expect(model.confirmedPlace?.parts == AddressParts(entrance: "А", apartment: "301"))
    }

    @Test("Door details belong to the address they were typed against")
    func partsDoNotFollowANewAddress() async throws {
        let model = PointPickerView.Model(
            initialPlace: PickedPlace(
                latitude: 55.75, longitude: 37.61,
                address: "Москва, Тверская, 6",
                parts: AddressParts(entrance: "А", floor: "3", apartment: "301")
            ),
            resolveAddress: { _, _ in "Москва, Каширское шоссе, 52" },
            searchPlace: { _, _ in PickedPlace(latitude: 55.64, longitude: 37.66, address: "Найдено") },
            expandLink: { _ in throw Unexpected() },
            locateOnce: { throw Unexpected() }
        )
        #expect(model.addressParts.entrance == "А", "editing the point it opened on keeps them")

        model.dropPin(latitude: 55.64, longitude: 37.66)
        #expect(model.addressParts.isEmpty,
                "entrance 3, flat 301 of a different building is a failed delivery")
        try await waitUntil { !model.isResolving }
        #expect(model.confirmedPlace?.parts == nil)
    }

    @Test("A searched address does not inherit the previous point's door details")
    func partsDoNotSurviveASearch() async throws {
        let model = model()
        model.dropPin(latitude: 55.75, longitude: 37.61)
        try await waitUntil { !model.isResolving }
        model.addressParts.apartment = "301"

        model.searchAsAddress("Каширское шоссе 52")
        #expect(model.addressParts.isEmpty)
    }

    @Test("Correcting a coarse fix by hand drops the approximation warning")
    func approximationDiesWithItsPin() async throws {
        let model = model(
            resolve: { _, _ in "Москва, где-то рядом" },
            locate: { (55.7558, 37.6173, 1200) }
        )
        model.continueAfterLocationPrompt()
        try await waitUntil { !model.isLocating && !model.isResolving }
        #expect(model.locationIsApproximate)

        model.dropPin(latitude: 55.646068, longitude: 37.668176)
        #expect(!model.locationIsApproximate,
                "the sender placed this one; the warning belonged to the fix, not the map")
    }

    @Test("System lookup errors collapse to one honest sentence, not kCLErrorDomain")
    func systemErrorsReadHuman() async throws {
        let model = model(resolve: { _, _ in throw URLError(.notConnectedToInternet) })
        model.dropPin(latitude: 55.75, longitude: 37.61)
        try await waitUntil { !model.isResolving }

        let text = try #require(model.lookupErrorText)
        #expect(!text.contains("Domain"), "raw system error text never reaches the bar")
        #expect(!text.contains("operation"))
    }

    @Test("While typing, matching recents pin above suggestions; an empty query pins none")
    func recentsMatchTheQuery() {
        let recents: [PointPickerView.SearchContent.Recent] = [
            .init(id: "a", address: "Москва, ул Москворечье, 6", detail: "Иван Петров"),
            .init(id: "b", address: "Москва, Арбат, 10", detail: ""),
        ]

        #expect(PointPickerView.SearchContent.matching(recents, query: "москворечье").map(\.address)
            == ["Москва, ул Москворечье, 6"])
        #expect(PointPickerView.SearchContent.matching(recents, query: "  ").isEmpty)
    }

    private struct Unexpected: Error {}
    private struct TimedOut: Error {}

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
}
