import Foundation
import Testing
@testable import YDelivery

/// The <doc:LinkGrammars> contract, row by row. Every expectation cites the table; the
/// two traps get their own suites. DMS strings (`55 45 20.9N …`) are a documented gap —
/// the URL grammars and decimal pairs cover every pasteable link.
@Suite("Map link grammars")
struct MapLinkTests {
    // MARK: Yandex

    @Test("Yandex pt is lon,lat — longitude first, per their docs")
    func yandexPoint() {
        let link = MapLink(pasted: "https://yandex.ru/maps/?pt=30.335429,59.944869&z=18")
        #expect(link == .point(
            .init(latitude: 59.944869, longitude: 30.335429),
            source: .yandexMaps
        ))
    }

    @Test("Yandex whatshere[point] is lon,lat and beats ll")
    func yandexWhatsHere() {
        let link = MapLink(
            pasted: "https://yandex.ru/maps/?ll=30.31,59.95&whatshere%5Bpoint%5D=37.444076,55.776788"
        )
        #expect(link == .point(
            .init(latitude: 55.776788, longitude: 37.444076),
            source: .yandexMaps
        ))
    }

    @Test("Yandex ll is the map center — the weakest signal, used only alone")
    func yandexCenterFallback() {
        let link = MapLink(pasted: "https://yandex.ru/maps/?ll=30.310182,59.951059&z=12")
        #expect(link == .point(
            .init(latitude: 59.951059, longitude: 30.310182),
            source: .yandexMaps
        ))
    }

    @Test("Yandex rtext is lat,lon — the documented opposite order — and offers both ends")
    func yandexRouteFlipsOrder() {
        let link = MapLink(
            pasted: "https://yandex.ru/maps/?rtext=59.967870,30.242658~59.898495,30.299559&rtt=auto"
        )
        #expect(link == .route(
            from: .init(latitude: 59.967870, longitude: 30.242658),
            to: .init(latitude: 59.898495, longitude: 30.299559),
            source: .yandexMaps
        ))
    }

    @Test(
        "A route with an unreadable stop is no route — a dropped one would move an end",
        arguments: [
            "broken~59.967870,30.242658~59.898495,30.299559",
            "59.967870,30.242658~broken~59.898495,30.299559",
            "59.967870,30.242658~59.898495,30.299559~broken",
        ]
    )
    func yandexRouteRejectsUnreadableStop(rtext: String) {
        let link = MapLink(pasted: "https://yandex.ru/maps/?rtext=\(rtext)&rtt=auto")
        #expect(link == .noCoordinates(source: .yandexMaps),
                "compactMap would have promoted an intermediate stop to an endpoint")
    }

    @Test(
        "2GIS directions reject an unreadable point for the same reason",
        arguments: [
            "broken|37.531542,55.736291|37.665247,55.759725",
            "37.531542,55.736291|broken|37.665247,55.759725",
            "37.531542,55.736291|37.665247,55.759725|broken",
        ]
    )
    func twoGISDirectionsRejectUnreadablePoint(points: String) {
        let link = MapLink(pasted: "https://2gis.ru/directions/points/\(points)")
        #expect(link == .noCoordinates(source: .twoGIS))
    }

    @Test(
        "A lookalike domain is not a provider — suffixes match on label boundaries",
        arguments: [
            "https://notyandex.ru/maps/?pt=37.62,55.75",
            "https://evilgoogle.com/maps/@55.75,37.62,15z",
            "https://not2gis.ru/geo/37.62,55.75",
            "https://fakemaps.apple.com.example.org/?ll=55.75,37.62",
        ]
    )
    func lookalikeDomainsAreNotProviders(link: String) {
        #expect(MapLink(pasted: link) == nil,
                "a suffix match would read an unrelated site's URL as a map point")
    }

    @Test("A real subdomain of a provider is still admitted by the host gate")
    func subdomainsStillParse() {
        // The path shape is the ordinary one; only the host is a subdomain here, which
        // is the half the boundary check changed.
        #expect(MapLink(pasted: "https://maps.yandex.ru/maps/?pt=37.668176,55.646068") == .point(
            .init(latitude: 55.646068, longitude: 37.668176),
            source: .yandexMaps
        ))
    }

    @Test("Yandex text may hold a bare lat,lon pair")
    func yandexSearchTextCoordinates() {
        let link = MapLink(pasted: "https://yandex.ru/maps/?text=55.762611,36.982528")
        #expect(link == .point(
            .init(latitude: 55.762611, longitude: 36.982528),
            source: .yandexMaps
        ))
    }

    @Test("A Yandex org card carries no coordinates — decline, never geocode a guess")
    func yandexOrgCardDeclines() {
        let link = MapLink(pasted: "https://yandex.ru/maps/org/1184371713")
        #expect(link == .noCoordinates(source: .yandexMaps))
    }

    @Test("A Yandex short link needs one GET before the rules apply")
    func yandexShortLink() {
        let url = URL(string: "https://yandex.ru/maps/-/CDUaELzY")!
        #expect(MapLink(pasted: url.absoluteString) == .shortLink(url, source: .yandexMaps))
    }

    // MARK: Google

    @Test("Google q and query are lat,lng")
    func googleQueryPin() {
        #expect(MapLink(pasted: "https://www.google.com/maps?q=55.7558,37.6173") == .point(
            .init(latitude: 55.7558, longitude: 37.6173),
            source: .googleMaps
        ))
        #expect(
            MapLink(pasted: "https://www.google.com/maps/search/?api=1&query=55.7558,37.6173")
                == .point(.init(latitude: 55.7558, longitude: 37.6173), source: .googleMaps)
        )
    }

    @Test("Google's data blob !3d!4d is the actual pin and beats the @ center")
    func googlePlaceBlobBeatsCenter() {
        let link = MapLink(
            pasted: "https://www.google.com/maps/place/Red+Square/@55.75,37.61,15z/data=!3m1!4b1!4m6!3m5!1s0x0:0x0!8m2!3d55.7539!4d37.6208"
        )
        #expect(link == .point(
            .init(latitude: 55.7539, longitude: 37.6208),
            source: .googleMaps
        ))
    }

    @Test("The @ path view is the map center — fallback only")
    func googleCenterFallback() {
        let link = MapLink(pasted: "https://www.google.com/maps/@55.7558,37.6173,15z")
        #expect(link == .point(
            .init(latitude: 55.7558, longitude: 37.6173),
            source: .googleMaps
        ))
    }

    @Test("Google short links expand before the rules apply")
    func googleShortLinks() {
        let url = URL(string: "https://maps.app.goo.gl/Abc123")!
        #expect(MapLink(pasted: url.absoluteString) == .shortLink(url, source: .googleMaps))
    }

    // MARK: 2GIS

    @Test("2GIS /geo/ is lon,lat")
    func twoGISPoint() {
        let link = MapLink(pasted: "https://2gis.ru/geo/82.683276,55.001485")
        #expect(link == .point(
            .init(latitude: 55.001485, longitude: 82.683276),
            source: .twoGIS
        ))
    }

    @Test("A 2GIS object id carries no coordinates")
    func twoGISObjectDeclines() {
        #expect(MapLink(pasted: "https://2gis.ru/geo/141476222740947") == .noCoordinates(source: .twoGIS))
        #expect(MapLink(pasted: "https://2gis.ru/firm/70000001006123456") == .noCoordinates(source: .twoGIS))
    }

    @Test("2GIS directions offer both ends, lon,lat with object ids stripped")
    func twoGISDirections() {
        let link = MapLink(
            pasted: "https://2gis.ru/directions/points/37.531542,55.736291;4504235282859269|37.665247,55.759725;4504235282859270"
        )
        #expect(link == .route(
            from: .init(latitude: 55.736291, longitude: 37.531542),
            to: .init(latitude: 55.759725, longitude: 37.665247),
            source: .twoGIS
        ))
    }

    @Test("A 2GIS short link expands first")
    func twoGISShortLink() {
        let url = URL(string: "https://go.2gis.com/7muvw")!
        #expect(MapLink(pasted: url.absoluteString) == .shortLink(url, source: .twoGIS))
    }

    // MARK: geo: and Apple

    @Test("geo: URIs are lat,lng, altitude and uncertainty ignored")
    func geoURI() {
        #expect(MapLink(pasted: "geo:55.7558,37.6173") == .point(
            .init(latitude: 55.7558, longitude: 37.6173),
            source: .geoURI
        ))
        #expect(MapLink(pasted: "geo:13.4125,103.8667,14") == .point(
            .init(latitude: 13.4125, longitude: 103.8667),
            source: .geoURI
        ))
    }

    @Test("The Android geo:0,0?q= extension carries the pair in the query")
    func geoURIAndroidExtension() {
        let link = MapLink(pasted: "geo:0,0?q=55.7558,37.6173(Красная площадь)")
        #expect(link == .point(
            .init(latitude: 55.7558, longitude: 37.6173),
            source: .geoURI
        ))
    }

    @Test("Apple classic ll and unified coordinate are lat,lng")
    func appleMaps() {
        #expect(MapLink(pasted: "https://maps.apple.com/?ll=48.85837,2.29448&q=Label") == .point(
            .init(latitude: 48.85837, longitude: 2.29448),
            source: .appleMaps
        ))
        #expect(
            MapLink(pasted: "https://maps.apple.com/place?coordinate=40.779092,-73.962932&name=X")
                == .point(.init(latitude: 40.779092, longitude: -73.962932), source: .appleMaps)
        )
    }

    @Test("Apple place-id and address forms carry no parseable coordinates")
    func applePlaceIDDeclines() {
        let link = MapLink(pasted: "https://maps.apple.com/place?place-id=I63802885C8189B2B")
        #expect(link == .noCoordinates(source: .appleMaps))
    }

    // MARK: Raw pairs

    @Test("A bare pair reads as lat,lon — the universal human convention")
    func rawPair() {
        #expect(MapLink(pasted: "55.7558, 37.6173") == .point(
            .init(latitude: 55.7558, longitude: 37.6173),
            source: .rawCoordinates
        ))
    }

    @Test("Hemisphere letters set the sign")
    func rawPairHemispheres() {
        #expect(MapLink(pasted: "55.7558N, 37.6173E") == .point(
            .init(latitude: 55.7558, longitude: 37.6173),
            source: .rawCoordinates
        ))
        #expect(MapLink(pasted: "33.8688S, 151.2093E") == .point(
            .init(latitude: -33.8688, longitude: 151.2093),
            source: .rawCoordinates
        ))
    }

    @Test("A hemisphere letter dictates the sign — a signed southern pair stays south")
    func rawPairSignedWithHemisphere() {
        // -33.8688S once double-negated into the northern hemisphere
        // (review, PR #18 post-merge).
        #expect(MapLink(pasted: "-33.8688S, 151.2093E") == .point(
            .init(latitude: -33.8688, longitude: 151.2093),
            source: .rawCoordinates
        ))
        #expect(MapLink(pasted: "55.7558N, -37.6173W") == .point(
            .init(latitude: 55.7558, longitude: -37.6173),
            source: .rawCoordinates
        ))
    }

    // MARK: DMS — the raw row's last form (YD-8)

    /// Expectations spell the parser's own `d + m/60 + s/3600` arithmetic so the
    /// comparison is exact rather than tolerance-based — hoisted to locals because
    /// the arithmetic inside `#expect` overran the type-checker once already.
    private static func moscow() -> MapLink.Parsed {
        .init(latitude: 55 + 45.0 / 60 + 20.9 / 3600,
              longitude: 37 + 37.0 / 60 + 2.8 / 3600)
    }

    @Test("DMS reads degrees, minutes, seconds — the grammar table's raw row")
    func dmsPair() {
        #expect(MapLink(pasted: "55 45 20.9N 37 37 2.8E") == .point(
            Self.moscow(), source: .rawCoordinates
        ))
    }

    @Test("DMS with degree/prime symbols and a comma separator reads identically")
    func dmsSymbolForms() {
        #expect(MapLink(pasted: "55°45′20.9″N, 37°37′2.8″E") == .point(
            Self.moscow(), source: .rawCoordinates
        ))
        // Decimal minutes, no seconds — the geocaching form.
        let minutesOnly = MapLink.Parsed(latitude: 55 + 45.348 / 60, longitude: 37 + 37.05 / 60)
        #expect(MapLink(pasted: "55°45.348′N, 37°37.05′E") == .point(
            minutesOnly, source: .rawCoordinates
        ))
    }

    @Test("Southern and western hemispheres carry the sign")
    func dmsHemisphereSigns() {
        let sydney = MapLink.Parsed(latitude: -(33 + 52.0 / 60 + 8.0 / 3600),
                                    longitude: 151 + 12.0 / 60 + 30.0 / 3600)
        #expect(MapLink(pasted: "33°52′08″S 151°12′30″E") == .point(
            sydney, source: .rawCoordinates
        ))
    }

    @Test("The letters label the axes — longitude-first reads as correctly")
    func dmsOrderFree() {
        #expect(MapLink(pasted: "37°37′2.8″E 55°45′20.9″N") == .point(
            Self.moscow(), source: .rawCoordinates
        ))
    }

    @Test(
        "A malformed DMS declines — the letterless list was never provable",
        arguments: [
            "55 60 20N 37 37E",      // minutes past 59
            "55 45 20N 37 37 99E",   // seconds past 59
            "55 45N 37 37N",         // two latitudes, no longitude
            "55 45 20.9 37 37 2.8",  // no letters — a bare number list
            "55.75 45N 37.61 37E",   // decimal degrees inside a DMS axis
            "55.7558,37.6173N",      // decimal pair, hemisphere on the wrong axis
            "95 45N 37 37E",         // latitude past 90
        ]
    )
    func dmsRejectsTheUnprovable(text: String) {
        #expect(MapLink(pasted: text) == nil)
    }

    @Test("A pt the grammar cannot read declines — ll is the map's center, not the mark")
    func unreadablePinDeclinesRatherThanRecentering() {
        // The marked place was unreadable; offering ll would look right and point
        // somewhere else (review, PR #18 post-merge).
        #expect(MapLink(pasted: "https://yandex.ru/maps/?pt=garbage&ll=30.31,59.95")
            == .noCoordinates(source: .yandexMaps))
        #expect(MapLink(pasted: "https://yandex.ru/maps/?whatshere%5Bpoint%5D=999,999&ll=30.31,59.95")
            == .noCoordinates(source: .yandexMaps))
    }

    // MARK: Not links

    @Test("Prose, empty strings, and unrelated URLs are not offered at all")
    func notALink() {
        #expect(MapLink(pasted: "Москва, Тверская 1") == nil)
        #expect(MapLink(pasted: "") == nil)
        #expect(MapLink(pasted: "https://example.com/?pt=30.3,59.9") == nil)
        #expect(MapLink(pasted: "check out https://yandex.ru") == nil)
    }

    @Test("A latitude beyond 90° fails the parse instead of shipping nonsense")
    func implausiblePairFails() {
        // Magnitude can only catch the flagrant case — west of the Urals both halves
        // are ≤ 90 and no parser can tell them apart, which is exactly why the paste
        // affordance always shows the resolved point before it joins the route.
        #expect(MapLink(pasted: "95.0, 37.6173") == nil)
        #expect(MapLink(pasted: "geo:137.6173,55.7558") == nil)
    }
}
