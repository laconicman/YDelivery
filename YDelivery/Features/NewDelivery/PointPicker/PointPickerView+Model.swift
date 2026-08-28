import CoreLocation
import MapKit
import Observation

extension PointPickerView {
    /// The picker's screen logic: autocomplete, tap-to-pin, and address resolution.
    ///
    /// The two network seams — reverse geocoding and place search — are injected closures,
    /// so every state transition here is testable without MapKit talking to the network.
    @Observable @MainActor
    final class Model {
        /// A completion the user can tap. Identity derives from the datum (R8), so the list
        /// keeps stable identities across the completer's rapid updates.
        nonisolated struct AddressSuggestion: Identifiable, Hashable, Sendable {
            let title: String
            let subtitle: String

            var id: String { "\(title)|\(subtitle)" }
        }

        /// Coordinates → display address. Defaults to `CLGeocoder`.
        typealias AddressResolver =
            @Sendable (_ latitude: Double, _ longitude: Double) async throws -> String

        /// Free-text query (+ optional region bias) → a concrete place. Defaults to
        /// `MKLocalSearch`.
        typealias PlaceSearcher =
            @Sendable (_ query: String, _ region: MKCoordinateRegion?) async throws -> PickedPlace

        private(set) var suggestions: [AddressSuggestion] = []
        private(set) var pin: PickedPlace?
        private(set) var isResolving = false
        private(set) var lookupError: (any Error)?

        /// The map's visible region, reported by the view; biases search results toward
        /// what the user is looking at.
        var visibleRegion: MKCoordinateRegion?

        var searchText = "" {
            didSet {
                guard searchText != oldValue else { return }
                completer.queryFragment = searchText
                if searchText.isEmpty { suggestions = [] }
            }
        }

        /// Screen-level derivation for the confirm bar (R5).
        var lookupErrorText: String? { lookupError?.localizedDescription }

        var pinAddress: String {
            get { pin?.address ?? "" }
            set {
                pin?.address = newValue
                // The geocoder proposes, the user disposes: typing takes the address over —
                // a late result must not overwrite it, and a failure it supersedes must not
                // keep shouting under the corrected text.
                lookupError = nil
                if isResolving {
                    lookupTask?.cancel()
                    isResolving = false
                }
            }
        }

        private let completer = MKLocalSearchCompleter()
        private var completerBridge: CompleterBridge?
        private let resolveAddress: AddressResolver
        private let searchPlace: PlaceSearcher
        private var lookupTask: Task<Void, Never>?

        init(
            initialPlace: PickedPlace? = nil,
            resolveAddress: @escaping AddressResolver = Model.geocoderResolver,
            searchPlace: @escaping PlaceSearcher = Model.localSearcher
        ) {
            pin = initialPlace
            self.resolveAddress = resolveAddress
            self.searchPlace = searchPlace
        }

        /// Consumes completer batches for as long as the screen lives. Run it from the root
        /// view's `.task`: structured concurrency, so SwiftUI cancels it on dismiss and the
        /// bridge (with its stream) releases with the screen — no stored task, no custom
        /// `deinit`. (`isolated deinit` would have carried an iOS 18.4 runtime floor.)
        func streamSuggestions() async {
            guard completerBridge == nil else { return }
            let bridge = CompleterBridge()
            completerBridge = bridge
            completer.delegate = bridge
            completer.resultTypes = [.address, .pointOfInterest]
            defer { completerBridge = nil }

            for await batch in bridge.updates {
                // A batch for an already-cleared query (selection just landed) would flash
                // stale suggestions back under the empty search field.
                if !searchText.isEmpty { suggestions = batch }
            }
        }

        /// A tap on the map: the pin moves immediately, the address arrives asynchronously
        /// and stays editable. A stale in-flight lookup is cancelled rather than raced.
        func dropPin(latitude: Double, longitude: Double) {
            pin = PickedPlace(latitude: latitude, longitude: longitude, address: "")
            beginLookup { [resolveAddress] in
                let address = try await resolveAddress(latitude, longitude)
                return PickedPlace(latitude: latitude, longitude: longitude, address: address)
            }
        }

        /// A tapped completion: resolve it to coordinates through the search seam.
        func select(_ suggestion: AddressSuggestion) {
            searchText = ""
            let query = suggestion.subtitle.isEmpty
                ? suggestion.title
                : "\(suggestion.title), \(suggestion.subtitle)"
            beginLookup { [searchPlace, visibleRegion] in
                try await searchPlace(query, visibleRegion)
            }
        }

        private func beginLookup(_ operation: @escaping @Sendable () async throws -> PickedPlace) {
            lookupTask?.cancel()
            lookupError = nil
            isResolving = true
            // Weak self, so an in-flight lookup does not pin a dismissed screen's model
            // alive until the network answers. Nothing cancels this task on deallocation —
            // it is superseded-cancelled by the next lookup, or completes naturally and
            // finds nobody to tell.
            lookupTask = Task { [weak self] in
                // A superseded task unwinds while its replacement is still in flight; only
                // the live task may declare resolution over, or the spinner vanishes and
                // Confirm enables against an empty address.
                defer { if !Task.isCancelled { self?.isResolving = false } }
                do {
                    let place = try await operation()
                    guard !Task.isCancelled else { return }
                    self?.pin = place
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.lookupError = error
                }
            }
        }

    }
}

// MARK: - Live seams

extension PointPickerView.Model {
    /// `CLGeocoder` is the reverse-geocoding tool at the iOS 17 floor (its iOS 26
    /// replacement, `MKReverseGeocodingRequest`, is above it). One request at a time, per
    /// its documentation — `beginLookup` already serializes by cancelling the predecessor.
    nonisolated static let geocoderResolver: AddressResolver = { latitude, longitude in
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { throw NoAddressFound() }
        return placemark.deliveryAddress
    }

    nonisolated static let localSearcher: PlaceSearcher = { query, region in
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if let region { request.region = region }
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw NoAddressFound() }
        let coordinate = item.placemark.coordinate
        return PickedPlace(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            address: item.placemark.deliveryAddress
        )
    }

    /// `LocalizedError`, so the confirm bar's red footer reads "No address found." rather
    /// than the generic "The operation couldn't be completed…" a bare `Error` renders as.
    nonisolated struct NoAddressFound: LocalizedError {
        var errorDescription: String? { String(localized: "No address found.") }
    }
}

// MARK: - Completer bridge

/// `MKLocalSearchCompleter` speaks through a delegate with no documented queue guarantee,
/// so the bridge is nonisolated and converts to `Sendable` values on the spot. Delivery is
/// an `AsyncStream` rather than per-callback hops: one continuation keeps batches ordered,
/// and `bufferingNewest(1)` drops stale intermediates so the consumer only ever renders the
/// latest set. Held strongly by the model; the completer's `delegate` is weak.
private nonisolated final class CompleterBridge: NSObject, MKLocalSearchCompleterDelegate {
    let updates: AsyncStream<[PointPickerView.Model.AddressSuggestion]>
    private let continuation: AsyncStream<[PointPickerView.Model.AddressSuggestion]>.Continuation

    override init() {
        (updates, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    deinit {
        continuation.finish()
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        continuation.yield(completer.results.map {
            .init(title: $0.title, subtitle: $0.subtitle)
        })
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        // Autocomplete failing is not worth an alert; the user keeps typing or taps the map.
        continuation.yield([])
    }
}

// MARK: - Address formatting

private nonisolated extension CLPlacemark {
    /// The address string a courier can act on: city first, then street-level detail — the
    /// Russian/Yandex convention ("Москва, Тверская, 1"). Falls back progressively — a bare
    /// coordinate pin in a park still deserves its best-effort name.
    var deliveryAddress: String {
        let street = [thoroughfare, subThoroughfare].compactMap(\.self).joined(separator: ", ")
        // `name` sometimes *is* the locality (a pin in a park, a city-level match) — using
        // it as the detail would read "Москва, Москва".
        let detail = street.isEmpty ? (name == locality ? nil : name) : street
        return [locality, detail].compactMap(\.self).joined(separator: ", ")
    }
}
