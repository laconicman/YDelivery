import SwiftUI
import UIKit
import YDeliveryKit

/// Root view of the point-picker sheet: search first (board `2a`), the map one row away.
/// Owns the model, reads the store, and wires both into the two stages — search and the
/// refine map — connected by a navigation push so Back is free.
///
/// Seeding `@State` from the initializer is deliberate here — a sheet is recreated per
/// presentation, so "first value wins" is exactly the wanted semantics for editing an
/// already-chosen place (which opens straight on the map, at the place).
struct PointPickerView: View {
    let prompt: LocalizedStringKey
    /// The chosen place, and what the selection has to say about the person at its door.
    let confirm: (PickedPlace, ContactChoice) -> Void
    /// A pasted route link fills both ends in one action (decision #9); `nil` hides
    /// that offer.
    let fillEnds: ((PickedPlace, PickedPlace) -> Void)?
    /// Who already stands at this point's door, so bookmarking it keeps them.
    let initialContact: Contact?

    @State private var model: Model
    @State private var pendingSave: PendingSave?
    /// Where an empty map starts when location is unavailable — set in Settings, plain
    /// preference, not a secret.
    @AppStorage("startCity") private var startCity = ""
    @Environment(StoreController.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// What a selection says about the person at the door. Refining a pin says nothing —
    /// whoever the row already had is still standing there. Choosing a remembered point
    /// speaks for the whole point: it carries its person, or it carries nobody, and
    /// either way that replaces what was there. Collapsing "nothing to say" into "nobody"
    /// left the courier calling the previous address's person (review, PR #18).
    enum ContactChoice: Hashable {
        case unchanged
        case replace(Contact?)
    }

    init(
        prompt: LocalizedStringKey,
        initialPlace: PickedPlace? = nil,
        initialContact: Contact? = nil,
        confirm: @escaping (PickedPlace, ContactChoice) -> Void,
        fillEnds: ((PickedPlace, PickedPlace) -> Void)? = nil
    ) {
        self.prompt = prompt
        self.confirm = confirm
        self.fillEnds = fillEnds
        self.initialContact = initialContact
        _model = State(initialValue: Model(initialPlace: initialPlace))
    }

    /// The point being named for the chips — `sheet(item:)` wants identity. It carries
    /// the contact as well as the place: a saved place is a whole point, and the chip
    /// that restores it hands back the person at its door (Design → "a point carries
    /// data, not coordinates"; review, PR #18).
    private struct PendingSave: Identifiable {
        let id = UUID()
        let place: PickedPlace
        let contact: Contact?
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            SearchContent(
                chips: store.savedPlaces.map {
                    SearchContent.Chip(id: $0.id, name: $0.name, symbol: $0.kind.symbol)
                },
                recents: store.recentPoints.map(SearchContent.Recent.init),
                historyUnavailable: store.historyUnavailable,
                searchText: $model.searchText,
                suggestions: model.suggestions,
                pasteState: model.pasteState,
                isLocating: model.isLocating,
                locationPromptVisible: model.locationPromptVisible,
                locationDenied: model.locationDenied,
                pickChip: { id in
                    // Chip → done: the whole point, contact included, no further steps
                    // (board 2a — the habitual sender's path).
                    guard let place = store.savedPlaces.first(where: { $0.id == id }) else { return }
                    confirm(PickedPlace(place.point), .replace(Contact(at: place.point)))
                    dismiss()
                },
                pickRecent: { id in
                    guard let point = store.recentPoints.first(
                        where: { StoreController.destinationKey($0) == id }
                    ) else { return }
                    confirm(PickedPlace(point), .replace(Contact(at: point)))
                    dismiss()
                },
                select: { model.select($0) },
                searchAsAddress: { model.searchAsAddress($0) },
                chooseOnMap: { model.chooseOnMap() },
                useMyLocation: { model.useMyLocation() },
                continueLocationPrompt: { model.continueAfterLocationPrompt() },
                dismissLocationPrompt: { model.locationPromptVisible = false },
                openSettings: {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                },
                paste: { model.paste($0) },
                placePreviewedPoint: { model.placePreviewedPoint() },
                fillRoute: fillEnds.map { fill in
                    {
                        guard let (from, to) = model.previewedRoute else { return }
                        fill(from, to)
                        dismiss()
                    }
                },
                dismissPaste: { model.dismissPaste() }
            )
            .navigationTitle(prompt)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $model.isRefining) {
                RefineContent(
                    pin: model.pin,
                    pinAddress: $model.pinAddress,
                    parts: $model.addressParts,
                    isResolving: model.isResolving,
                    isApproximate: model.locationIsApproximate,
                    errorText: model.lookupErrorText,
                    saveUnavailableReason: store.canSavePlaces
                        ? nil
                        : StoreController.StoreUnavailable().localizedDescription,
                    fallbackRegion: model.startRegion,
                    onTap: { model.dropPin(latitude: $0, longitude: $1) },
                    onVisibleRegionChange: { model.visibleRegion = $0 },
                    savePlace: {
                        if let place = model.confirmedPlace {
                            pendingSave = PendingSave(place: place, contact: initialContact)
                        }
                    },
                    done: {
                        guard let place = model.confirmedPlace else { return }
                        // Refining says nothing about people; the row keeps whoever it had.
                        confirm(place, .unchanged)
                        dismiss()
                    }
                )
                .navigationTitle("Refine the point")
                .navigationBarTitleDisplayMode(.inline)
            }
            .task { await model.streamSuggestions() }
            .task { await store.refresh() }
            .task(id: startCity) { await model.resolveStartCity(startCity) }
        }
        .sheet(item: $pendingSave) { pending in
            SavePlaceSheet(address: pending.place.displayAddress) { name, kind in
                try await store.save(
                    SavedPlace(
                        name: name,
                        kind: kind,
                        point: RoutePoint(pending.place, contact: pending.contact)
                    )
                )
            }
        }
    }
}

extension PointPickerView.SearchContent.Recent {
    /// A remembered point as its row: the address, and the person who was at the door —
    /// never a timestamp (decision #10). Bridging lives at the root's side of the seam.
    init(_ point: RoutePoint) {
        self.init(
            id: StoreController.destinationKey(point),
            address: point.address,
            detail: point.contactName ?? ""
        )
    }
}

#Preview("Fresh") {
    PointPickerView(prompt: "Where to pick up?", confirm: { _, _ in })
        .environment(StoreController(orderStore: nil, placeStore: nil))
}

#Preview("Editing a chosen place — opens on the map") {
    PointPickerView(
        prompt: "Where to deliver?",
        initialPlace: PickedPlace(
            latitude: 55.646068,
            longitude: 37.668176,
            address: "Москва, Каширское шоссе, 52",
            parts: AddressParts(entrance: "2", apartment: "15")
        ),
        confirm: { _, _ in }
    )
    .environment(StoreController(orderStore: nil, placeStore: nil))
}
