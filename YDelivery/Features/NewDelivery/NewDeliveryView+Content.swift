import SwiftUI

extension NewDeliveryView {
    /// Pure presentation: two route-end rows and a swap affordance. Plain values in,
    /// intents out (R1/R2).
    struct Content: View {
        let pickupAddress: String?
        let dropoffAddress: String?
        let canSwap: Bool
        let pick: (RouteEnd) -> Void
        let swapEnds: () -> Void

        var body: some View {
            List {
                Section {
                    EndRow(
                        label: "Pickup",
                        systemImage: "shippingbox.and.arrow.backward",
                        address: pickupAddress,
                        select: { pick(.pickup) }
                    )
                    EndRow(
                        label: "Drop-off",
                        systemImage: "house",
                        address: dropoffAddress,
                        select: { pick(.dropoff) }
                    )
                } footer: {
                    Text("Parcel details and priced offers come after the route.")
                }

                if canSwap {
                    Button("Swap pickup and drop-off", systemImage: "arrow.up.arrow.down", action: swapEnds)
                }
            }
        }
    }
}

extension NewDeliveryView.Content {
    /// One end of the route: shows the chosen address or invites choosing one.
    struct EndRow: View {
        let label: LocalizedStringKey
        let systemImage: String
        let address: String?
        let select: () -> Void

        var body: some View {
            Button(action: select) {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label)
                                .font(.headline)
                            Text(address ?? "Choose on the map")
                                .font(.subheadline)
                                .foregroundStyle(address == nil ? .tertiary : .secondary)
                        }
                    } icon: {
                        Image(systemName: systemImage)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

#Preview("End row: chosen and unchosen") {
    List {
        NewDeliveryView.Content.EndRow(
            label: "Pickup",
            systemImage: "shippingbox.and.arrow.backward",
            address: "Москва, ул Москворечье, 6",
            select: {}
        )
        NewDeliveryView.Content.EndRow(
            label: "Drop-off",
            systemImage: "house",
            address: nil,
            select: {}
        )
    }
}

#Preview("Empty draft") {
    NewDeliveryView.Content(
        pickupAddress: nil,
        dropoffAddress: nil,
        canSwap: false,
        pick: { _ in },
        swapEnds: {}
    )
}

#Preview("Route complete") {
    NewDeliveryView.Content(
        pickupAddress: "Москва, ул Москворечье, 6",
        dropoffAddress: "Москва, Каширское шоссе, 52",
        canSwap: true,
        pick: { _ in },
        swapEnds: {}
    )
}
