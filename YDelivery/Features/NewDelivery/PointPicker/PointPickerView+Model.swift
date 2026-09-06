import CoreLocation
import MapKit
import Observation
import YDeliveryKit

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

        /// Short link → the full URL it redirects to. Defaults to one `URLSession` HEAD.
        typealias LinkExpander = @Sendable (_ url: URL) async throws -> URL

        /// One position fix. Defaults to `CLLocationUpdate.liveUpdates()`, whose first
        /// update also raises the system prompt when authorization is undetermined.
        typealias LocationFix = @Sendable () async throws -> (latitude: Double, longitude: Double, accuracy: Double)

        private(set) var suggestions: [AddressSuggestion] = []
        private(set) var pin: PickedPlace?
        private(set) var isResolving = false
        private(set) var lookupError: (any Error)?

        /// Whether the refine stage (the map, «Уточните точку») is showing. Search is
        /// the picker's home; the map is one row away, never a mode (board `2a`).
        var isRefining = false

        /// The parts of the address the pin cannot know — edited on the refine stage,
        /// carried out with the confirmed place.
        var addressParts = AddressParts()

        /// The paste affordance's card, when active (board `2a`, frames 4–5).
        private(set) var pasteState: PasteState?

        /// The considerate-acquisition explainer, shown before the system's own prompt.
        var locationPromptVisible = false
        private(set) var isLocating = false
        private(set) var locationDenied = false
        /// True when the fix is coarse (~1 km) — the map invites correcting the pin.
        private(set) var locationIsApproximate = false

        /// The map's visible region, reported by the view; biases the autocomplete and the
        /// final place search toward what the user is looking at.
        var visibleRegion: MKCoordinateRegion? {
            didSet {
                if let visibleRegion { completer.region = visibleRegion }
            }
        }

        var searchText = "" {
            didSet {
                guard searchText != oldValue else { return }
                completer.queryFragment = searchText
                if searchText.isEmpty { suggestions = [] }
            }
        }

        /// Screen-level derivation for the confirm bar (R5). Crafted errors speak for
        /// themselves; system errors (geocoder offline, dead network) collapse to one
        /// honest sentence — `kCLErrorDomain` is not a thing to render.
        var lookupErrorText: String? {
            guard let lookupError else { return nil }
            return (lookupError as? LocalizedError)?.errorDescription
                ?? String(localized: "Couldn't name this point. Check the address, type it in, or move the pin.")
        }

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
        private let expandLink: LinkExpander
        private let locateOnce: LocationFix
        private var lookupTask: Task<Void, Never>?
        private var pasteTask: Task<Void, Never>?
        private var locationTask: Task<Void, Never>?

        init(
            initialPlace: PickedPlace? = nil,
            resolveAddress: @escaping AddressResolver = Model.geocoderResolver,
            searchPlace: @escaping PlaceSearcher = Model.localSearcher,
            expandLink: @escaping LinkExpander = Model.urlSessionExpander,
            locateOnce: @escaping LocationFix = Model.liveUpdatesFix
        ) {
            pin = initialPlace
            self.resolveAddress = resolveAddress
            self.searchPlace = searchPlace
            self.expandLink = expandLink
            self.locateOnce = locateOnce
            // Editing an already-chosen place starts on the map, at the place.
            isRefining = initialPlace != nil
            addressParts = initialPlace?.parts ?? AddressParts()
        }

        /// Everything that describes *this* pin and must not outlive it: the door details
        /// typed against it, and whether the fix that placed it was too coarse to name a
        /// door. Every path that chooses a genuinely new point calls this, so an entrance
        /// and floor cannot ride along to a different address and a corrected pin cannot
        /// keep an approximation warning it no longer earns (review, PR #18).
        ///
        /// Opening the picker on an already-chosen place does *not* call it — that place
        /// arrives with its own parts, and editing it is not choosing a new point.
        /// A fix the sender is no longer waiting for. Any selection they make themselves
        /// supersedes a pending «Моё местоположение» — otherwise the fix lands late and
        /// drops its pin over the address they just chose (review, PR #18). Called from
        /// the selection paths, never from the fix's own completion, which must be free
        /// to place the pin it was asked for.
        private func retireLocationFix() {
            locationTask?.cancel()
            locationTask = nil
            isLocating = false
        }

        private func adoptNewPoint(isApproximate: Bool = false) {
            addressParts = AddressParts()
            locationIsApproximate = isApproximate
        }

        /// The confirmed result: the pin plus whatever parts were filled on the refine
        /// stage. `nil` while nothing is confirmed-able.
        var confirmedPlace: PickedPlace? {
            guard var place = pin else { return nil }
            place.parts = addressParts.isEmpty ? nil : addressParts
            return place
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

        /// «Выбрать на карте» — the refine stage with nothing placed yet; a tap will
        /// place the pin.
        func chooseOnMap() {
            isRefining = true
        }

        /// A tap on the map: the pin moves immediately, the address arrives asynchronously
        /// and stays editable. A stale in-flight lookup is cancelled rather than raced.
        ///
        /// `isApproximate` travels with the call that places the pin rather than being set
        /// around it, so a coarse fix cannot leave its warning behind on a point the
        /// sender later corrected by hand (review, PR #18).
        func dropPin(latitude: Double, longitude: Double, isApproximate: Bool = false) {
            isRefining = true
            adoptNewPoint(isApproximate: isApproximate)
            pin = PickedPlace(latitude: latitude, longitude: longitude, address: "")
            beginLookup { [resolveAddress] in
                let address = try await resolveAddress(latitude, longitude)
                return PickedPlace(latitude: latitude, longitude: longitude, address: address)
            }
        }

        /// A tapped completion: resolve it to coordinates through the search seam and
        /// land on the map for the one Done (board `2a`, «Уточните точку»).
        func select(_ suggestion: AddressSuggestion) {
            searchText = ""
            let query = suggestion.subtitle.isEmpty
                ? suggestion.title
                : "\(suggestion.title), \(suggestion.subtitle)"
            searchAsAddress(query)
        }

        /// The nothing-found escape hatch: run the raw text through the place search —
        /// «Искать … как адрес».
        func searchAsAddress(_ query: String) {
            searchText = ""
            isRefining = true
            adoptNewPoint()
            // The point being replaced is gone the moment the search starts. Leaving it
            // meant a failed search re-enabled Done over the *previous* destination —
            // now stripped of the door details `adoptNewPoint` just cleared, so it would
            // confirm somewhere the sender had already moved on from, incompletely
            // (review, PR #18).
            pin = nil
            beginLookup { [searchPlace, visibleRegion] in
                try await searchPlace(query, visibleRegion)
            }
        }

        private func beginLookup(_ operation: @escaping @Sendable () async throws -> PickedPlace) {
            lookupTask?.cancel()
            retireLocationFix()
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

        // MARK: Paste

        /// What a pasted string became — the states of board `2a`'s paste frames. The
        /// point is *always* previewed before it may join the route: coordinate order
        /// flips per provider, and a silent swap puts the pin in the Barents Sea
        /// (<doc:LinkGrammars>, the two traps).
        nonisolated enum PasteState: Hashable {
            /// Following a short link — the one network-dependent class.
            case expanding
            /// Naming the parsed coordinates so the preview is verifiable.
            case resolving
            case preview(PickedPlace, source: MapLink.Source)
            case routePreview(from: PickedPlace, to: PickedPlace, source: MapLink.Source)
            case failed(PasteFailure)
        }

        nonisolated enum PasteFailure: Hashable {
            /// The short link could not be expanded — offline copy, original kept so the
            /// sender can open it in a maps app instead.
            case couldNotExpand(original: URL)
            /// A recognizable provider link that names a place without coordinates.
            case noCoordinates
            /// Not a map link at all.
            case notALink
        }

        /// Runs pasted text through the <doc:LinkGrammars> rules.
        func paste(_ text: String) {
            pasteTask?.cancel()
            guard let link = MapLink(pasted: text) else {
                pasteState = .failed(.notALink)
                return
            }
            handle(link, mayExpand: true)
        }

        func dismissPaste() {
            pasteTask?.cancel()
            pasteState = nil
        }

        /// «Поставить точку» — the previewed point moves to the map for the one Done.
        func placePreviewedPoint() {
            guard case .preview(let place, _) = pasteState else { return }
            pasteState = nil
            retireLocationFix()
            adoptNewPoint()
            pin = place
            isRefining = true
        }

        /// Both ends of a previewed route link, for the caller to fill in one action
        /// (decision #9).
        var previewedRoute: (from: PickedPlace, to: PickedPlace)? {
            guard case .routePreview(let from, let to, _) = pasteState else { return nil }
            return (from, to)
        }

        private func handle(_ link: MapLink, mayExpand: Bool) {
            switch link {
            case .point(let parsed, let source):
                pasteState = .resolving
                pasteTask = Task { [weak self, resolveAddress] in
                    let address = (try? await resolveAddress(parsed.latitude, parsed.longitude)) ?? ""
                    guard !Task.isCancelled else { return }
                    self?.pasteState = .preview(
                        PickedPlace(latitude: parsed.latitude, longitude: parsed.longitude, address: address),
                        source: source
                    )
                }
            case .route(let from, let to, let source):
                pasteState = .resolving
                pasteTask = Task { [weak self, resolveAddress] in
                    let fromAddress = (try? await resolveAddress(from.latitude, from.longitude)) ?? ""
                    let toAddress = (try? await resolveAddress(to.latitude, to.longitude)) ?? ""
                    guard !Task.isCancelled else { return }
                    self?.pasteState = .routePreview(
                        from: PickedPlace(latitude: from.latitude, longitude: from.longitude, address: fromAddress),
                        to: PickedPlace(latitude: to.latitude, longitude: to.longitude, address: toAddress),
                        source: source
                    )
                }
            case .shortLink(let url, _):
                guard mayExpand else {
                    // An expansion that yields another short link is a loop, not a point.
                    pasteState = .failed(.noCoordinates)
                    return
                }
                pasteState = .expanding
                pasteTask = Task { [weak self, expandLink] in
                    do {
                        let expanded = try await expandLink(url)
                        guard !Task.isCancelled else { return }
                        if let followUp = MapLink(pasted: expanded.absoluteString) {
                            self?.handle(followUp, mayExpand: false)
                        } else {
                            self?.pasteState = .failed(.noCoordinates)
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.pasteState = .failed(.couldNotExpand(original: url))
                    }
                }
            case .noCoordinates:
                pasteState = .failed(.noCoordinates)
            }
        }

        // MARK: Location

        /// «Моё местоположение». Undetermined authorization shows the considerate
        /// explainer first — the system prompt appears only after the sender says
        /// continue (Roadmap → Phase 2, the NetworkObserverSample pattern). Denial is
        /// a rendered state, not an error.
        func useMyLocation() {
            locationDenied = false
            switch CLLocationManager().authorizationStatus {
            case .notDetermined:
                locationPromptVisible = true
            case .denied, .restricted:
                locationDenied = true
            default:
                acquireLocation()
            }
        }

        /// The explainer's «Continue»: now the system may ask.
        func continueAfterLocationPrompt() {
            locationPromptVisible = false
            acquireLocation()
        }

        nonisolated struct LocationDenied: Error {}

        private func acquireLocation() {
            locationTask?.cancel()
            isLocating = true
            locationTask = Task { [weak self, locateOnce] in
                defer { if !Task.isCancelled { self?.isLocating = false } }
                do {
                    let fix = try await locateOnce()
                    guard !Task.isCancelled else { return }
                    // This fix is arriving, so it is no longer pending: drop the handle
                    // before placing the pin, or `dropPin`'s selection path would retire
                    // the very task delivering it.
                    self?.locationTask = nil
                    self?.isLocating = false
                    // Say so, and invite correcting the pin (board `2a`).
                    self?.dropPin(
                        latitude: fix.latitude,
                        longitude: fix.longitude,
                        // Coarser than ~500 m (Reduced Accuracy is ~1–20 km) cannot name
                        // a door.
                        isApproximate: fix.accuracy > 500
                    )
                } catch is LocationDenied {
                    guard !Task.isCancelled else { return }
                    self?.locationDenied = true
                } catch let error as CLError where error.code == .denied {
                    // liveUpdates can also answer denial as its own thrown error.
                    guard !Task.isCancelled else { return }
                    self?.locationDenied = true
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

    /// One GET; `URLSession` follows the redirect chain and hands back where it landed —
    /// the only network step the paste affordance ever takes.
    ///
    /// GET rather than HEAD: shorteners are not obliged to answer HEAD, and the ones this
    /// grammar supports redirect on GET. Answering HEAD with 405 made every short link
    /// from such a provider report "could not expand" (review, PR #18). The body is
    /// discarded; only where it landed matters.
    nonisolated static let urlSessionExpander: LinkExpander = { url in
        // Headers only. A short link may redirect anywhere, and `data(from:)` buffers
        // whatever it finds there — an arbitrary body from an arbitrary host, for a
        // request whose entire purpose is to learn one URL (review, PR #18). `bytes`
        // returns once the response head has arrived; cancelling the task there means
        // the body is never fetched.
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        bytes.task.cancel()
        guard let final = response.url, final.scheme == "https" || final.scheme == "http"
        else { throw URLError(.badServerResponse) }
        return final
    }

    /// The first usable fix from `CLLocationUpdate.liveUpdates()`, which also raises the
    /// system authorization prompt when it is still undetermined. Denial and restriction
    /// surface as ``Model/LocationDenied`` so the caller renders the state — read from
    /// the manager, because the update's own convenience flags are iOS 18-only and the
    /// floor is 17.
    nonisolated static let liveUpdatesFix: LocationFix = {
        for try await update in CLLocationUpdate.liveUpdates() {
            if let location = update.location {
                return (
                    location.coordinate.latitude,
                    location.coordinate.longitude,
                    location.horizontalAccuracy
                )
            }
            switch CLLocationManager().authorizationStatus {
            case .denied, .restricted: throw LocationDenied()
            default: continue // undetermined (prompt showing) or a fix still warming up
            }
        }
        throw CancellationError()
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
