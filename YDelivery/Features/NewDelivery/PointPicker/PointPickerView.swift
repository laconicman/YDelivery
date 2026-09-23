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
    /// The chosen point, whole: the place and the person at its door — `nil` person
    /// means nobody, stated. One flow answers both questions (Round 5, decision #40).
    let confirm: (PickedPlace, Contact?) -> Void
    /// A pasted route link fills both ends in one action (decision #9); `nil` hides
    /// that offer.
    let fillEnds: ((PickedPlace, PickedPlace) -> Void)?
    @State private var model: Model
    @State private var pendingSave: PendingSave?
    /// The chip being renamed/retyped — the `3e` editor, same sheet as first save.
    @State private var editingPlace: SavedPlace?
    /// The chip a destructive forget still has to be confirmed against.
    @State private var pendingDelete: SavedPlace?
    /// Where an empty map starts when location is unavailable — set in Settings, plain
    /// preference, not a secret.
    @AppStorage("startCity") private var startCity = ""
    @Environment(StoreController.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(
        prompt: LocalizedStringKey,
        initialPlace: PickedPlace? = nil,
        initialContact: Contact? = nil,
        confirm: @escaping (PickedPlace, Contact?) -> Void,
        fillEnds: ((PickedPlace, PickedPlace) -> Void)? = nil
    ) {
        self.prompt = prompt
        self.confirm = confirm
        self.fillEnds = fillEnds
        _model = State(initialValue: Model(initialPlace: initialPlace, initialContact: initialContact))
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
                historyUnavailable: store.pickerMemoryUnavailable,
                searchText: $model.searchText,
                suggestions: model.suggestions,
                pasteState: model.pasteState,
                isLocating: model.isLocating,
                locationPromptVisible: model.locationPromptVisible,
                locationDenied: model.locationDenied,
                pickChip: { id in
                    // Chip → done: the whole point, contact included, no further steps
                    // (board 2a — the habitual sender's path stays one tap).
                    guard let place = store.savedPlaces.first(where: { $0.id == id }) else { return }
                    confirm(PickedPlace(place.point), Contact(at: place.point))
                    dismiss()
                },
                editChip: { id in
                    editingPlace = store.savedPlaces.first(where: { $0.id == id })
                },
                deleteChip: { id in
                    pendingDelete = store.savedPlaces.first(where: { $0.id == id })
                },
                pickRecent: { id in
                    guard let point = store.recentPoints.first(
                        where: { $0.destinationKey == id }
                    ) else { return }
                    confirm(PickedPlace(point), Contact(at: point))
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
                    isResolving: model.isResolving,
                    isApproximate: model.locationIsApproximate,
                    errorText: model.lookupErrorText,
                    fallbackRegion: model.startRegion,
                    onTap: { model.dropPin(latitude: $0, longitude: $1) },
                    onVisibleRegionChange: { model.visibleRegion = $0 },
                    continueToDescribe: { model.continueToDescribe() }
                )
                .navigationTitle("Refine the point")
                .navigationBarTitleDisplayMode(.inline)
                // The flow's end, stacked on the map: door details and the person on
                // one screen, Back returning to the address (Round 5, decision #40;
                // author, 2026-09-14 — one navigation stack, not two sheets).
                .navigationDestination(isPresented: $model.isDescribing) {
                    DescribeContent(
                        addressLine: model.confirmedPlace?.displayAddress ?? model.pinAddress,
                        addressLacksBuilding: model.pin?.lacksBuilding == true,
                        changeAddress: { model.isDescribing = false },
                        parts: $model.addressParts,
                        contact: $model.contact,
                        saveUnavailableReason: store.canSavePlaces
                            ? nil
                            : StoreController.StoreUnavailable().localizedDescription,
                        bookmark: {
                            if let place = model.confirmedPlace {
                                pendingSave = PendingSave(place: place, contact: model.confirmedContact)
                            }
                        },
                        save: {
                            guard let place = model.confirmedPlace else { return }
                            confirm(place, model.confirmedContact)
                            dismiss()
                        }
                    )
                    .navigationTitle("The point")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .task { await model.streamSuggestions() }
            .task { await store.refresh() }
            .task(id: startCity) { await model.resolveStartCity(startCity) }
        }
        // Every running task answers this sheet's question and no other's: dismissal
        // retires the location fix, the lookup, and a paste expansion alike. On the
        // *stack*, not on the search stage — attached there, every push to the map
        // fired it and cancelled the very lookup the map was waiting to display
        // (caught while framing the DeepWiki reviewer pass, 2026-09-14; the flaw
        // shipped with the PR #28 widening).
        .onDisappear { model.retireOngoingWork() }
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
        .sheet(item: $editingPlace) { place in
            // Same point, new label or kind — the store's destination-key dedupe
            // adopts the row's identity, and the explicit id is belt and suspenders.
            SavePlaceSheet(address: place.point.address, editing: place) { name, kind in
                try await store.save(
                    SavedPlace(id: place.id, name: name, kind: kind, point: place.point)
                )
            }
        }
        .confirmationDialog(
            "Forget this place?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { place in
            Button("Delete «\(place.name)»", role: .destructive) {
                pendingDelete = nil
                Task { await store.deletePlace(place.id) }
            }
            Button("Keep it", role: .cancel) { pendingDelete = nil }
        }
    }
}

extension PointPickerView.SearchContent.Recent {
    /// A remembered point as its row: the address, and the person who was at the door —
    /// never a timestamp (decision #10). Bridging lives at the root's side of the seam.
    init(_ point: RoutePoint) {
        self.init(
            id: point.destinationKey,
            address: point.address,
            detail: point.contactName ?? ""
        )
    }
}

#Preview("Fresh") {
    PointPickerView(prompt: "Where to pick up?", confirm: { _, _ in })
        .environment(StoreController(database: nil))
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
    .environment(StoreController(database: nil))
}
