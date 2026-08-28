import SwiftUI

/// Root view of the New Delivery flow. Owns the draft (screen-local state) and coordinates
/// the point-picker sheet; parcel details and offers arrive in the next Phase 1 slice
/// (Roadmap).
struct NewDeliveryView: View {
    @State private var model = Model()
    @State private var pickingEnd: RouteEnd?

    var body: some View {
        NavigationStack {
            Content(
                pickupAddress: model.pickup?.displayAddress,
                dropoffAddress: model.dropoff?.displayAddress,
                canSwap: model.canSwap,
                pick: { pickingEnd = $0 },
                swapEnds: { model.swapEnds() }
            )
            .navigationTitle("New Delivery")
            .sheet(item: $pickingEnd) { end in
                PointPickerView(
                    prompt: end.prompt,
                    initialPlace: model[end],
                    confirm: { model[end] = $0 }
                )
            }
        }
    }
}

/// Which end of the route a picker session is choosing. `Identifiable` so it can drive
/// `sheet(item:)` directly.
nonisolated enum RouteEnd: Identifiable, CaseIterable, Sendable {
    case pickup
    case dropoff

    var id: Self { self }
}

extension RouteEnd {
    var prompt: LocalizedStringKey {
        switch self {
        case .pickup: "Where to pick up?"
        case .dropoff: "Where to deliver?"
        }
    }
}

#Preview {
    NewDeliveryView()
}
