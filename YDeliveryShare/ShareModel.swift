import CoreLocation
import UniformTypeIdentifiers
import YDeliveryKit

/// The extension's half of the app's identity — the App Group it hands the
/// draft through, and the one URL it opens. The values are the app's own
/// (`AppGroup`/`DeepLink` in the app target), respelled because an extension
/// cannot import the app — the widget target's `WidgetIdentity`/`WidgetLink`
/// pull the same stunt.
nonisolated enum ShareIdentity {
    static let appGroupID = "group.com.learnable.YDelivery"
    /// `ydelivery://share` — the handoff verb the app parses.
    static let sharedDraftURL = URL(string: "ydelivery://share")!
}

/// The share sheet's flow (board `5d`, "ways in"): read the attachment,
/// resolve it to a point, offer the end pick and the «Откуда» saved-places
/// row, then hand the app a `SharedDraft`. Distinct phases, not show/hide —
/// a share that resolves to nothing earns an honest card, not a silent sheet.
@MainActor @Observable
final class ShareModel {
    enum Phase {
        /// Attachments still reading / a geocode in flight.
        case resolving
        /// A point is aboard — the card shows it.
        case ready
        /// Nothing resolvable arrived — the card says so and only cancels.
        case failed
    }

    private(set) var phase: Phase = .resolving
    /// The resolved shared point, door parts aboard when the text spelled them.
    private(set) var point: RoutePoint?
    /// «Это точка доставки» — the shared point fills the destination end by
    /// default and flips to the origin in the menu.
    var end: SharedDraft.End = .dropoff
    /// The «Откуда»/«Куда» row's pick — the saved place whose point rides
    /// along already resolved, so the app consumes without a join.
    var otherPlace: SavedPlace.ID?
    /// The app's saved places, exported to the group file — this extension
    /// never opens the database (Schema → the widget contract).
    let places: [SavedPlace]

    init(places: [SavedPlace]? = nil) {
        self.places = places ?? SavedPlacesFile.read(inAppGroup: ShareIdentity.appGroupID)
    }

    /// What «В доставку» writes — nil only before resolution, and the button
    /// is dead until then.
    func sharedDraft() -> SharedDraft? {
        guard let point else { return nil }
        let other = otherPlace.flatMap { id in places.first { $0.id == id } }?.point
        return SharedDraft(sharedAt: .now, point: point, end: end, otherEnd: other)
    }

    /// The whole ingest: attachments → a resolved point. A Maps URL seeds the
    /// coordinate itself (no geocode needed); shared text geocodes through
    /// the detector's candidates, the whole message as the last guess.
    func load(context: NSExtensionContext?) async {
        var text: String?
        var seed: SharedAddress.MapsSeed?
        for provider in context?.attachments ?? [] {
            if seed == nil,
               provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = await provider.sharedURL() {
                seed = SharedAddress.mapsSeed(from: url)
            }
            if text == nil,
               provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let shared = await provider.sharedText() {
                text = shared
            }
        }

        if let seed {
            point = await resolve(seed: seed)
        } else if let text {
            point = await resolve(text: text)
        }
        phase = point == nil ? .failed : .ready
    }

    /// A Maps share resolves without guessing — the pin is the link's own
    /// coordinate; the address is the link's postal line when it has one,
    /// else a reverse geocode, else the pin's label.
    private func resolve(seed: SharedAddress.MapsSeed) async -> RoutePoint? {
        var address = seed.address
        if address == nil {
            address = await reverseGeocode(
                latitude: seed.latitude, longitude: seed.longitude)
        }
        return RoutePoint(
            latitude: seed.latitude, longitude: seed.longitude,
            address: address ?? seed.name ?? "")
    }

    /// A text share geocodes its candidates best-first; the message's own
    /// spelling stays the address — the geocoder proposes coordinates, the
    /// sender's words stay theirs (the picker's same rule), and the card says
    /// the guess can be wrong before it ever reaches an order.
    private func resolve(text: String) async -> RoutePoint? {
        let parts = SharedAddress.doorParts(in: text)
        for candidate in SharedAddress.addressCandidates(in: text) {
            guard let mark = try? await CLGeocoder()
                .geocodeAddressString(candidate).first,
                  let coordinate = mark.location?.coordinate
            else { continue }
            return RoutePoint(
                latitude: coordinate.latitude, longitude: coordinate.longitude,
                address: Self.address(from: mark, fallback: candidate),
                addressParts: parts.isEmpty ? nil : parts)
        }
        return nil
    }

    private func reverseGeocode(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        else { return nil }
        return Self.address(from: mark, fallback: "")
    }

    /// «City, Street N» — the fullname convention every address in the app
    /// spells (the picker's geocode composes the same two pieces). The shared
    /// text is the fallback: a sender's own words beat a sparse placemark.
    private nonisolated static func address(
        from mark: CLPlacemark, fallback: String
    ) -> String {
        let street = [mark.thoroughfare, mark.subThoroughfare]
            .compactMap { $0 }.joined(separator: " ")
        let composed = [mark.locality, street.isEmpty ? nil : street]
            .compactMap { $0 }.joined(separator: ", ")
        return composed.isEmpty ? fallback : composed
    }
}

private extension NSExtensionContext {
    /// Every attachment every item offers — the order they came in.
    var attachments: [NSItemProvider] {
        (inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    }
}

/// `loadObject` ships callback-only — the continuations are its async
/// spelling, one per type so only Sendable values cross. A provider that
/// can't produce the type answers `nil`, same as one that never offered it.
private extension NSItemProvider {
    func sharedURL() async -> URL? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: NSURL.self) { object, _ in
                continuation.resume(returning: (object as? NSURL) as URL?)
            }
        }
    }

    func sharedText() async -> String? {
        await withCheckedContinuation { continuation in
            _ = loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString) as String?)
            }
        }
    }
}

#if DEBUG
extension ShareModel {
    /// The ready card for previews — a resolved text share with door parts
    /// and a place list, so the canvas exercises the real branches.
    static func preview() -> ShareModel {
        let model = ShareModel(places: [
            SavedPlace(
                id: UUID(), name: "Home", kind: .home,
                point: RoutePoint(
                    latitude: 55.75, longitude: 37.59,
                    address: "Москва, Тверская, 6",
                    contactName: "Иван", contactPhone: "+79123456789")),
        ])
        var parts = AddressParts()
        parts.entrance = "2"
        parts.apartment = "15"
        model.point = RoutePoint(
            latitude: 55.65, longitude: 37.64,
            address: "Москва, Каширское шоссе, 52",
            addressParts: parts)
        model.phase = .ready
        return model
    }
}
#endif
