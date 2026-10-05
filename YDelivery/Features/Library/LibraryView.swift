import SFSafeSymbols
import SwiftUI
import YDeliveryKit

/// Root view of the Library tab — the sender's saved places and parcel
/// templates, bridged from the store's memory into the content's rows. This is
/// the *curate* path: places are earned at the use path (the picker's bookmark,
/// «Save as a template»), so the list re-describes, pins and forgets — a place's
/// editor rewrites everything but the point itself; parcels can additionally be
/// authored here, where a template is the noun.
struct LibraryView: View {
    @Environment(StoreController.self) private var store

    /// A place a row menu asked to forget — held for the confirm dialog, never
    /// deleted by the menu itself (the picker's `pendingDelete` pattern, carried
    /// here whole).
    @State private var pendingDeletePlace: SavedPlace?
    /// Same ceremony for a template.
    @State private var pendingDeleteTemplate: ParcelTemplate?
    /// The place `PlaceEditor` is re-describing — `sheet(item:)` identity
    /// is the place's own.
    @State private var editingPlace: SavedPlace?
    /// The template the editor is re-shaping; `isAdding` asks the same editor
    /// for a new one — one form, two doors.
    @State private var editingTemplate: ParcelTemplate?
    @State private var isAddingTemplate = false
    /// The Places «+»'s picked point — `pickedPlace` is written by the picker
    /// still mid-dismissal, `namingPlace` fires the naming sheet only after the
    /// picker has left: two sheets on one view cannot overlap (DeepWiki pass —
    /// the codebase chains no sheets off a dismissal yet).
    @State private var pickedPlace: PendingNewPlace?
    @State private var namingPlace: PendingNewPlace?
    @State private var isPickingPlace = false

    /// A point the picker just answered, awaiting its name and kind.
    private struct PendingNewPlace: Identifiable {
        let id = UUID()
        let place: PickedPlace
        let contact: Contact?
    }

    var body: some View {
        NavigationStack {
            Content(
                placeRows: store.savedPlaces.map(Content.PlaceRow.init(place:)),
                placesError: store.placesError?.localizedDescription,
                parcelRows: store.parcelTemplates.map(Content.ParcelRow.init(template:)),
                parcelsError: store.templatesError?.localizedDescription,
                pinPlace: { id in
                    guard let place = store.savedPlaces.first(where: { $0.id == id }) else { return }
                    Task { await store.setPlacePinned(id, pinned: !place.pinned) }
                },
                editPlace: { id in
                    editingPlace = store.savedPlaces.first(where: { $0.id == id })
                },
                deletePlace: { id in
                    pendingDeletePlace = store.savedPlaces.first(where: { $0.id == id })
                },
                pinParcel: { id in
                    guard let template = store.parcelTemplates.first(where: { $0.id == id }) else { return }
                    Task { await store.setTemplatePinned(id, pinned: !template.pinned) }
                },
                editParcel: { id in
                    editingTemplate = store.parcelTemplates.first(where: { $0.id == id })
                },
                deleteParcel: { id in
                    pendingDeleteTemplate = store.parcelTemplates.first(where: { $0.id == id })
                },
                addPlace: { isPickingPlace = true },
                addParcel: { isAddingTemplate = true }
            )
                .navigationTitle("Library")
                // The editor rewrites name, kind, the door details and the
                // person; the pin and address stay — a place is its point
                // (task doc ruling, owner 2026-10-05), and a describe-only
                // save never moves geo (YD-27).
                .sheet(item: $editingPlace) { place in
                    PlaceEditor(place: place) { try await store.save($0) }
                }
                .sheet(item: $editingTemplate) { template in
                    ParcelTemplateEditor(template: template) { try await store.save($0) }
                }
                .sheet(isPresented: $isAddingTemplate) {
                    ParcelTemplateEditor { try await store.save($0) }
                }
                // The «+» asks the full pick flow — search, map, the door details —
                // then the same naming sheet a bookmark gets. No route ends to fill:
                // the library's place stands alone.
                .sheet(isPresented: $isPickingPlace, onDismiss: {
                    if let picked = pickedPlace {
                        namingPlace = picked
                        pickedPlace = nil
                    }
                }) {
                    // No saved chips here — picking one could only rename the
                    // place it already is.
                    PointPickerView(
                        prompt: "New place",
                        confirm: { place, contact in
                            pickedPlace = PendingNewPlace(place: place, contact: contact)
                        },
                        showsSavedPlaces: false)
                }
                .sheet(item: $namingPlace) { pending in
                    PointPickerView.SavePlaceSheet(address: pending.place.displayAddress, standsAlone: true) { name, kind in
                        try await store.save(SavedPlace(
                            name: name, kind: kind,
                            point: RoutePoint(pending.place, contact: pending.contact)))
                    }
                }
                .confirmationDialog(
                    "Forget this place?",
                    isPresented: Binding(
                        get: { pendingDeletePlace != nil },
                        set: { if !$0 { pendingDeletePlace = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: pendingDeletePlace
                ) { place in
                    Button("Delete «\(place.name)»", role: .destructive) {
                        pendingDeletePlace = nil
                        Task { await store.deletePlace(place.id) }
                    }
                    Button("Keep it", role: .cancel) { pendingDeletePlace = nil }
                }
                .confirmationDialog(
                    "Forget this template?",
                    isPresented: Binding(
                        get: { pendingDeleteTemplate != nil },
                        set: { if !$0 { pendingDeleteTemplate = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: pendingDeleteTemplate
                ) { template in
                    Button("Delete «\(template.name)»", role: .destructive) {
                        pendingDeleteTemplate = nil
                        Task { await store.deleteTemplate(template.id) }
                    }
                    Button("Keep it", role: .cancel) { pendingDeleteTemplate = nil }
                }
        }
    }
}

#Preview {
    // A databaseless store reads as the empty library — the populated states
    // live on Content's previews, which take rows without a store.
    LibraryView()
        .environment(StoreController(database: nil))
}
