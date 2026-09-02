import Foundation

/// What the map's own routing says about the draft's route: how far, how long, and the
/// path to draw. Information, never the CTA (decision #13) — and replaced wholesale by
/// provider figures when offers land, because two times on one screen is a bug report
/// (decision #14).
nonisolated struct RouteEstimate: Hashable, Sendable {
    var distanceMeters: Double
    var travelTime: TimeInterval

    /// One coordinate run per leg, in travel order — the map draws them as the route.
    var legs: [[Coordinate]]

    nonisolated struct Coordinate: Hashable, Sendable {
        var latitude: Double
        var longitude: Double
    }
}

nonisolated extension RouteEstimate {
    /// The bar's one line: «12.4 km · ~35 min». Display formatting lives here, not in a
    /// view body (R5); measurements localize themselves (km/versts are the locale's
    /// problem, not ours).
    var summary: String {
        let distance = Measurement<UnitLength>(value: distanceMeters, unit: .meters)
            .converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        let minutes = Duration.seconds(travelTime)
            .formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return String(localized: "\(distance) · ~\(minutes)")
    }
}
