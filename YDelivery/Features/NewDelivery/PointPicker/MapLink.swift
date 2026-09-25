import Foundation
import RegexBuilder

/// What a pasted string turned out to carry — the outcome of the <doc:LinkGrammars>
/// contract. The parser keys on host + parameter and **never guesses coordinate order**:
/// west of the Urals both values are ≤ 90, so magnitude cannot disambiguate, and a silent
/// lon/lat swap puts the pin in the Barents Sea. Whatever comes out is *always* shown to
/// the sender as a verifiable point before it joins the route.
nonisolated enum MapLink: Hashable, Sendable {
    /// A single point, with the provider named so the preview can say where it came from.
    case point(Parsed, source: Source)
    /// A route — both ends, offered as from/to in one action (decision #9).
    case route(from: Parsed, to: Parsed, source: Source)
    /// A short link that must be expanded over the network before the rules apply.
    case shortLink(URL, source: Source)
    /// A recognizable provider link that carries no coordinates at all (an org card, an
    /// object id) — decline gracefully, never geocode a guess.
    case noCoordinates(source: Source)

    /// Whether this link already answers the paste with coordinates — the redirect
    /// gate stops expanding at the first hop that does (review, PR #18, edited ask).
    var isReadable: Bool {
        switch self {
        case .point, .route: true
        case .shortLink, .noCoordinates: false
        }
    }

    /// The hosts this grammar reads — the single list the parser dispatch and the
    /// redirect gate both consult, so "a host the expander may contact" and "a host
    /// the parser understands" cannot drift apart (review, PR #28: an allowlist beats
    /// reasoning about where arbitrary hostnames might resolve).
    nonisolated static func isProviderHost(_ host: String) -> Bool {
        host.isWithin("yandex.ru") || host.isWithin("yandex.com")
            || host == "maps.app.goo.gl" || host == "goo.gl" || host.isWithin("google.com")
            || host.isWithin("2gis.ru") || host == "go.2gis.com"
            || host.isWithin("maps.apple.com")
    }

    /// A coordinate pair as parsed — plain degrees, order already normalized to lat/lon.
    nonisolated struct Parsed: Hashable, Sendable {
        var latitude: Double
        var longitude: Double

        /// Both halves must be plausible degrees; a swapped pair east of 90°E fails this
        /// and the parse, which is the only cheap tripwire the format allows.
        var isPlausible: Bool {
            (-90.0...90.0).contains(latitude) && (-180.0...180.0).contains(longitude)
        }
    }

    nonisolated enum Source: Hashable, Sendable {
        case yandexMaps
        case googleMaps
        case twoGIS
        case geoURI
        case appleMaps
        case rawCoordinates
    }
}

// `nonisolated` on every extension: the project defaults new members onto the main actor
// (`SWIFT_DEFAULT_ACTOR_ISOLATION`), and an extension does not inherit the annotation
// from the type it extends — an unmarked member here would carry a hidden main-actor
// assertion into pure parsing code (it did: SIGTRAP in the first test run).
nonisolated extension MapLink {
    /// Parses a pasted string against the <doc:LinkGrammars> table. `nil` means "not a
    /// map link at all" — the paste affordance simply does not offer it.
    init?(pasted text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let raw = Self.rawCoordinatePair(trimmed) {
            self = raw
            return
        }
        guard let url = URL(string: trimmed) else { return nil }
        if let geo = Self.geoURI(url) {
            self = geo
            return
        }
        guard let host = url.host()?.lowercased(), Self.isProviderHost(host) else { return nil }
        let parsed: MapLink? = if host.isWithin("yandex.ru") || host.isWithin("yandex.com") {
            Self.yandexMaps(url)
        } else if host == "maps.app.goo.gl" || host == "goo.gl" || host.isWithin("google.com") {
            Self.googleMaps(url, host: host)
        } else if host.isWithin("2gis.ru") || host == "go.2gis.com" {
            Self.twoGIS(url, host: host)
        } else if host.isWithin("maps.apple.com") {
            Self.appleMaps(url)
        } else {
            nil
        }
        guard let parsed else { return nil }
        self = parsed
    }

    // MARK: Providers

    /// Yandex Maps: `pt`/`whatshere[point]`/`ll` are **lon,lat**; `rtext` is
    /// **lat,lon~lat,lon** (the documented opposite order); `text` may carry a bare
    /// lat,lon pair; `/maps/-/` is a short link; an org card has no coordinates.
    private static func yandexMaps(_ url: URL) -> MapLink? {
        guard url.path().contains("/maps") else { return nil }
        if url.path().contains("/maps/-/") {
            return .shortLink(url, source: .yandexMaps)
        }
        let query = url.queryItems
        // Strongest signal first: an explicit point beats the map's own center. And a
        // point parameter that is *present but unreadable* declines rather than falling
        // through — `ll` is the map's center, not the marked place, and offering it
        // would look right while pointing somewhere else (review, PR #18 post-merge;
        // same rule as rtext below).
        for name in ["pt", "whatshere[point]"] {
            if let value = query[name] {
                guard let pair = Parsed(lonLat: value), pair.isPlausible else {
                    return .noCoordinates(source: .yandexMaps)
                }
                return .point(pair, source: .yandexMaps)
            }
        }
        if let rtext = query["rtext"] {
            let segments = rtext.components(separatedBy: "~")
            let ends = segments.compactMap { Parsed(latLon: $0) }
            // Every segment must parse. Dropping one silently promotes an intermediate
            // stop to an endpoint — a route that looks right and delivers somewhere else,
            // which is the failure this grammar exists to prevent (review, PR #18).
            if ends.count == segments.count, ends.count >= 2, ends.allSatisfy(\.isPlausible) {
                return .route(from: ends[0], to: ends[ends.count - 1], source: .yandexMaps)
            }
            // A route we recognise but cannot read declines as itself. Falling through
            // would end at "not a map link", which is untrue of a link the user really
            // did copy from Yandex Maps.
            return .noCoordinates(source: .yandexMaps)
        }
        if let text = query["text"].flatMap({ Parsed(latLon: $0) }), text.isPlausible {
            return .point(text, source: .yandexMaps)
        }
        if let ll = query["ll"].flatMap({ Parsed(lonLat: $0) }), ll.isPlausible {
            // Map center — the weakest signal, used only when nothing else spoke.
            return .point(ll, source: .yandexMaps)
        }
        if url.path().contains("/maps/org/") {
            return .noCoordinates(source: .yandexMaps)
        }
        return nil
    }

    /// Google Maps: `q`/`query` and the place blob `!3d{lat}!4d{lng}` are **lat,lng**;
    /// `@lat,lng,zoom` is the map center — fallback only; short hosts expand first.
    private static func googleMaps(_ url: URL, host: String) -> MapLink? {
        if host == "maps.app.goo.gl" || host == "goo.gl" {
            return .shortLink(url, source: .googleMaps)
        }
        guard url.path().contains("/maps") else { return nil }
        let query = url.queryItems
        for name in ["q", "query"] {
            if let pair = query[name].flatMap({ Parsed(latLon: $0) }), pair.isPlausible {
                return .point(pair, source: .googleMaps)
            }
        }
        // The data blob names the actual pin; prefer it over the `@` center. Decoded
        // path throughout — `URL` percent-encodes what it lets through.
        let path = url.path(percentEncoded: false)
        if let blob = path.firstMatch(of: /!3d(-?[0-9.]+)!4d(-?[0-9.]+)/),
           let latitude = Double(blob.1), let longitude = Double(blob.2) {
            let pair = Parsed(latitude: latitude, longitude: longitude)
            if pair.isPlausible { return .point(pair, source: .googleMaps) }
        }
        if let at = path.firstMatch(of: /@(-?[0-9.]+),(-?[0-9.]+)/),
           let latitude = Double(at.1), let longitude = Double(at.2) {
            let pair = Parsed(latitude: latitude, longitude: longitude)
            if pair.isPlausible { return .point(pair, source: .googleMaps) }
        }
        return nil
    }

    /// 2GIS: `/geo/lon,lat` and directions points are **lon,lat**; numeric ids carry no
    /// coordinates; `go.2gis.com` is a short link.
    private static func twoGIS(_ url: URL, host: String) -> MapLink? {
        if host == "go.2gis.com" {
            return .shortLink(url, source: .twoGIS)
        }
        // Decoded: the `|` between directions points arrives percent-encoded.
        let path = url.path(percentEncoded: false)
        if path.contains("/directions/points/") {
            let segments = path
                .components(separatedBy: "/points/").last?
                .components(separatedBy: "|") ?? []
            let points = segments.compactMap { segment in
                Parsed(lonLat: segment.components(separatedBy: ";")[0])
            }
            // As with `rtext`: a dropped segment would hand the route a different end.
            if points.count == segments.count, points.count >= 2, points.allSatisfy(\.isPlausible) {
                return .route(from: points[0], to: points[points.count - 1], source: .twoGIS)
            }
            return .noCoordinates(source: .twoGIS)
        }
        if let geo = path.firstMatch(of: #//geo/(-?[0-9.]+),(-?[0-9.]+)/#),
           let longitude = Double(geo.1), let latitude = Double(geo.2) {
            let pair = Parsed(latitude: latitude, longitude: longitude)
            if pair.isPlausible { return .point(pair, source: .twoGIS) }
        }
        if path.contains("/geo/") || path.contains("/firm/") {
            return .noCoordinates(source: .twoGIS)
        }
        return nil
    }

    /// Apple Maps: classic `ll` and unified `coordinate` are **lat,lng**; place-id forms
    /// carry no coordinates; `address=` needs geocoding, which the paste path declines.
    private static func appleMaps(_ url: URL) -> MapLink? {
        let query = url.queryItems
        for name in ["ll", "coordinate"] {
            if let pair = query[name].flatMap({ Parsed(latLon: $0) }), pair.isPlausible {
                return .point(pair, source: .appleMaps)
            }
        }
        if query["place-id"] != nil || query["address"] != nil || query["q"] != nil {
            return .noCoordinates(source: .appleMaps)
        }
        return nil
    }

    /// RFC 5870 `geo:` URIs are **lat,lng[,alt]**, with the Android `?q=lat,lng(label)`
    /// extension; `;u=` uncertainty may trail the pair.
    private static func geoURI(_ url: URL) -> MapLink? {
        guard url.scheme?.lowercased() == "geo" else { return nil }
        let body = url.absoluteString.dropFirst("geo:".count)
        let beforeParams = body.components(separatedBy: CharacterSet(charactersIn: ";?"))[0]
        if let pair = Parsed(latLon: beforeParams), pair.isPlausible,
           pair.latitude != 0 || pair.longitude != 0 {
            return .point(pair, source: .geoURI)
        }
        // Android extension: geo:0,0?q=lat,lng(label)
        if let q = url.queryItems["q"] {
            let coordsPart = q.components(separatedBy: "(")[0]
            if let pair = Parsed(latLon: coordsPart), pair.isPlausible {
                return .point(pair, source: .geoURI)
            }
        }
        return nil
    }

    /// A bare pair — `55.7558, 37.6173`, hemisphere letters allowed — reads as
    /// **lat,lon**, the universal human convention (matches geo:/Apple/Google).
    /// DMS strings fall through to ``dmsCoordinatePair`` — the grammar table's
    /// last raw row (YD-8).
    private static func rawCoordinatePair(_ text: String) -> MapLink? {
        guard let match = text.wholeMatch(
            of: /(-?[0-9]{1,3}(?:\.[0-9]+)?)\s*([NSns])?\s*[,;]\s*(-?[0-9]{1,3}(?:\.[0-9]+)?)\s*([EWew])?/
        ) else { return dmsCoordinatePair(text) }
        guard var latitude = Double(match.1), var longitude = Double(match.3) else { return nil }
        // A hemisphere letter *dictates* the sign — negating an already signed number
        // flipped `-33.8688S` into the northern hemisphere (review, PR #18 post-merge).
        if let hemisphere = match.2 {
            latitude = hemisphere.lowercased() == "s" ? -abs(latitude) : abs(latitude)
        }
        if let hemisphere = match.4 {
            longitude = hemisphere.lowercased() == "w" ? -abs(longitude) : abs(longitude)
        }
        let pair = Parsed(latitude: latitude, longitude: longitude)
        guard pair.isPlausible else { return nil }
        return .point(pair, source: .rawCoordinates)
    }

    // MARK: DMS

    private static func dmsCoordinatePair(_ text: String) -> MapLink? {
        // One DMS axis: integer degrees, minutes, optional seconds, a *mandatory*
        // hemisphere letter — `55 45 20.9N`, `55°45′20.9″N`, decimal-minutes
        // `55°45.348′N`. The letter is what makes a bare number list a coordinate
        // at all; a letterless `55 45 20.9 37 37 2.8` is unprovable and declines.
        // Kept local rather than `static` — `Regex` is not `Sendable`, and the
        // literals compile into the binary either way.
        let axis = /([0-9]{1,3})[°\s]+([0-9]{1,2}(?:\.[0-9]+)?)(?:['′\s]+([0-9]{1,2}(?:\.[0-9]+)?))?['′\s"″]*([NSnsEWew])/
        // Two lettered axes — comma or whitespace between. Order is irrelevant:
        // the letters label each axis (the never-guess-order rule of the rest).
        let grammar = Regex { axis; /[,;\s]+/; axis }
        guard let match = text.wholeMatch(of: grammar),
              let first = Self.dmsComponent(match.1, minutes: match.2, seconds: match.3, hemisphere: match.4),
              let second = Self.dmsComponent(match.5, minutes: match.6, seconds: match.7, hemisphere: match.8)
        else { return nil }
        let latitude = first.isLatitude ? first : second
        let longitude = first.isLatitude ? second : first
        guard latitude.isLatitude, !longitude.isLatitude else { return nil }
        let pair = Parsed(latitude: latitude.value, longitude: longitude.value)
        guard pair.isPlausible else { return nil }
        return .point(pair, source: .rawCoordinates)
    }

    /// One axis → signed decimal degrees and whether it is a latitude. Minutes and
    /// seconds must stay under 60, degrees inside the hemisphere's bound —
    /// `91°…N` declines rather than wrapping.
    private static func dmsComponent(
        _ degrees: Substring, minutes: Substring, seconds: Substring?, hemisphere: Substring
    ) -> (value: Double, isLatitude: Bool)? {
        guard let d = Double(degrees), let m = Double(minutes) else { return nil }
        let s: Double
        if let seconds {
            guard let parsed = Double(seconds) else { return nil }
            s = parsed
        } else {
            s = 0
        }
        guard m < 60, s < 60 else { return nil }
        let letter = hemisphere.lowercased()
        let isLatitude = letter == "n" || letter == "s"
        guard isLatitude ? d <= 90 : d <= 180 else { return nil }
        let magnitude = d + m / 60 + s / 3600
        return (letter == "s" || letter == "w" ? -magnitude : magnitude, isLatitude)
    }
}

nonisolated extension MapLink.Parsed {
    /// From a `lat,lon` string — geo:, Apple, Google, Yandex `rtext`, raw pairs.
    fileprivate init?(latLon string: String) {
        guard let (first, second) = Self.pair(from: string) else { return nil }
        self.init(latitude: first, longitude: second)
    }

    /// From a `lon,lat` string — Yandex web parameters, 2GIS.
    fileprivate init?(lonLat string: String) {
        guard let (first, second) = Self.pair(from: string) else { return nil }
        self.init(latitude: second, longitude: first)
    }

    private static func pair(from string: String) -> (Double, Double)? {
        let parts = string.components(separatedBy: ",")
        guard parts.count >= 2,
              let first = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let second = Double(parts[1].trimmingCharacters(in: .whitespaces))
        else { return nil }
        return (first, second)
    }
}

private nonisolated extension URL {
    /// Decoded query items, last occurrence winning — enough for every grammar above.
    var queryItems: [String: String] {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { return [:] }
        return items.reduce(into: [:]) { result, item in
            result[item.name] = item.value
        }
    }
}

private nonisolated extension String {
    /// Whether this host is `domain` itself or a subdomain of it, matched on DNS label
    /// boundaries. A bare `hasSuffix` accepts `notyandex.ru` and `evilgoogle.com`, which
    /// would let an unrelated site's URL be read as a provider's map point and previewed
    /// as a place (review, PR #18).
    func isWithin(_ domain: String) -> Bool {
        self == domain || hasSuffix(".\(domain)")
    }
}
