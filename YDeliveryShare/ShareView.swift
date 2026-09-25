import SFSafeSymbols
import SwiftUI
import YDeliveryKit

/// The sheet itself (board `5d`): the found address, its door chips, the
/// «Это точка доставки» end pick, the «Откуда»/«Куда» saved-places row, and
/// the disclaimer that text-parsed addresses can misread. Actions are the
/// sheet's only verbs — a cancelled share writes nothing.
struct ShareView: View {
    /// `@Bindable` — the pickers write the end pick and the place row back
    /// onto the model the controller owns.
    @Bindable var model: ShareModel
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Send to YDelivery")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("New delivery", action: confirm)
                            .disabled(model.point == nil)
                    }
                }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .resolving:
            ProgressView("Reading the share…")
        case .failed:
            ContentUnavailableView(
                "No address found",
                systemSymbol: .mappinSlash,
                description: Text("Share a message or a map link that names a place.")
            )
        case .ready:
            List {
                foundAddress
                endsSection
            }
        }
    }

    private var foundAddress: some View {
        Section {
            if let point = model.point {
                Text(point.address.isEmpty ? "Pinned location" : point.address)
                    .font(.body)
                doorParts(point)
            }
        } header: {
            Text("Found an address")
        } footer: {
            Text("The address is guessed from the text — check the pin before ordering.")
        }
    }

    /// The door details the text spelled, each its own row — the same chips
    /// the draft's callout shows, so what the share understood is what the
    /// draft keeps.
    @ViewBuilder private func doorParts(_ point: RoutePoint) -> some View {
        if let parts = point.addressParts {
            if !parts.entrance.isEmpty { Text("Entrance \(parts.entrance)") }
            if !parts.intercom.isEmpty { Text("Intercom \(parts.intercom)") }
            if !parts.floor.isEmpty { Text("Floor \(parts.floor)") }
            if !parts.apartment.isEmpty { Text("Flat or office \(parts.apartment)") }
        }
    }

    private var endsSection: some View {
        Section {
            Picker(selection: $model.end) {
                Text("This is the destination")
                    .tag(SharedDraft.End.dropoff)
                Text("This is the origin")
                    .tag(SharedDraft.End.pickup)
            } label: {
                Text("This is the destination")
            }
            .pickerStyle(.menu)

            if !model.places.isEmpty {
                Picker(selection: $model.otherPlace) {
                    Text("Choose on the map")
                        .tag(SavedPlace.ID?.none)
                    ForEach(model.places) { place in
                        Text(place.name)
                            .tag(SavedPlace.ID?.some(place.id))
                    }
                } label: {
                    Text(model.end == .dropoff ? "Pick-up point" : "Delivery point")
                }
                .pickerStyle(.menu)
            }
        }
    }
}
