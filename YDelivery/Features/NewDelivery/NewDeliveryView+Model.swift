import Observation

extension NewDeliveryView {
    /// The flow's draft: which places bound the route. Owned by `RootView`, one level
    /// above the sheet that renders it (R7: one owner, as low as the lifetime allows) —
    /// dismissing the flow parks the draft, because navigation must never destroy one
    /// (Design → "The tab bar goes").
    @Observable @MainActor
    final class Model {
        var pickup: PickedPlace?
        var dropoff: PickedPlace?

        /// Both ends chosen — the gate for everything downstream (offers, creation).
        var isRouteComplete: Bool { pickup != nil && dropoff != nil }

        /// Swapping is only meaningful once there is something on each end to exchange —
        /// with one end empty it would just *move* the address, which reads as data loss.
        var canSwap: Bool { isRouteComplete }

        func swapEnds() {
            swap(&pickup, &dropoff)
        }

        subscript(end: RouteEnd) -> PickedPlace? {
            get {
                switch end {
                case .pickup: pickup
                case .dropoff: dropoff
                }
            }
            set {
                switch end {
                case .pickup: pickup = newValue
                case .dropoff: dropoff = newValue
                }
            }
        }
    }
}
