import SwiftUI

/// Root view of the New Delivery flow, presented as a sheet — the compose idiom. The draft
/// arrives from `RootView`, which owns it: Close parks the draft rather than destroying
/// it, so the button says Close, not Cancel. Parcel details and offers arrive with the
/// draft screen (Roadmap → Phase 2).
struct NewDeliveryView: View {
    let draft: Model
    @State private var pickingEnd: RouteEnd?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Content(
                pickupAddress: draft.pickup?.displayAddress,
                dropoffAddress: draft.dropoff?.displayAddress,
                canSwap: draft.canSwap,
                pick: { pickingEnd = $0 },
                swapEnds: { draft.swapEnds() }
            )
            .navigationTitle("New Delivery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $pickingEnd) { end in
                PointPickerView(
                    prompt: end.prompt,
                    initialPlace: draft[end],
                    confirm: { draft[end] = $0 }
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

#Preview("Empty draft") {
    NewDeliveryView(draft: NewDeliveryView.Model())
}

#Preview("Route complete") {
    let draft = NewDeliveryView.Model()
    draft.pickup = PickedPlace(
        latitude: 55.646068,
        longitude: 37.668176,
        address: "Москва, ул Москворечье, 6"
    )
    draft.dropoff = PickedPlace(
        latitude: 55.652212,
        longitude: 37.648210,
        address: "Москва, Каширское шоссе, 52"
    )
    return NewDeliveryView(draft: draft)
}
