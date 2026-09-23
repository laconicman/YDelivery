import Foundation
import YDeliveryKit

extension RoutePoint {
    /// What makes two remembered points *the same delivery destination*, so the two
    /// things that deduplicate against each other agree on what "same" means.
    ///
    /// The address alone is not enough. Flat 12 and flat 46 of one building share a
    /// street address and are different doors with different people behind them; keeping
    /// only the newest would offer a recent that restores the wrong apartment and the
    /// wrong contact (review, PR #18). The door details and the coordinates are part of
    /// the identity for exactly that reason.
    /// Lives on the point itself: the picker's row ids, the recents dedupe, and the
    /// store's place-adoption all deduplicate by it, so they cannot disagree.
    nonisolated var destinationKey: String {
        let address = address.lowercased().trimmingCharacters(in: .whitespaces)
        let parts = addressParts.map {
            "\($0.entrance)|\($0.floor)|\($0.apartment)|\($0.intercom)".lowercased()
        } ?? ""
        // Five decimals is about a metre — enough to separate two entrances of one
        // building, coarse enough that the same pin re-read stays one memory.
        let coordinates = String(
            format: "%.5f,%.5f", latitude, longitude
        )
        return "\(address)#\(parts)#\(coordinates)"
    }
}
