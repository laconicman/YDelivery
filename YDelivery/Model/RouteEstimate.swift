import Foundation

/// What the map's own routing says about the draft's route: how far, and the path
/// to draw. Information, never the CTA (decision #13) — and *distance only*,
/// always: two times on one screen is a bug report, so the provider's windows are
/// the time of record and the MKDirections ETA is gone with the offers that
/// outrank it (decision #14, implemented — the walking fallback keeps the curve
/// and the distance true; YD-31).
nonisolated struct RouteEstimate: Hashable, Sendable {
    var distanceMeters: Double

    /// One coordinate run per leg, in travel order — the map draws them as the route.
    var legs: [[Coordinate]]

    nonisolated struct Coordinate: Hashable, Sendable {
        var latitude: Double
        var longitude: Double
    }
}

nonisolated extension RouteEstimate {
    /// The bar's one line: «12.4 km». Display formatting lives here, not in a
    /// view body (R5); measurements localize themselves (km/versts are the locale's
    /// problem, not ours).
    var summary: String {
        Measurement<UnitLength>(value: distanceMeters, unit: .meters)
            .converted(to: .kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }
}
