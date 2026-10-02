import SFSafeSymbols
import SwiftUI
import YDeliveryKit

/// Root view of the Library tab — the sender's saved places and parcel
/// templates, bridged from the store's memory into the content's rows. This is
/// the *curate* path: places are earned at the use path (the picker's star,
/// «Save as a template»), so the list only renames, retypes, pins and forgets
/// — parcels can additionally be authored here, where a template is the noun.
struct LibraryView: View {
    @Environment(StoreController.self) private var store

    /// A place a row menu asked to forget — held for the confirm dialog, never
    /// deleted by the menu itself (the picker's `pendingDelete` pattern, carried
    /// here whole).
    @State private var pendingDeletePlace: SavedPlace?
    /// Same ceremony for a template.
    @State private var pendingDeleteTemplate: ParcelTemplate?
    /// The place `SavePlaceSheet` is renaming/retyping — `sheet(item:)` identity
    /// is the place's own.
    @State private var editingPlace: SavedPlace?
    /// The template the editor is re-shaping; `isAdding` asks the same editor
    /// for a new one — one form, two doors.
    @State private var editingTemplate: ParcelTemplate?
    @State private var isAddingTemplate = false

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
                addParcel: { isAddingTemplate = true }
            )
                .navigationTitle("Library")
                // Rename/retype only — the point is uneditable by construction
                // (task doc «curate-only»): a place is its point plus a name and
                // a kind, and moving it would make it a different place.
                .sheet(item: $editingPlace) { place in
                    PointPickerView.SavePlaceSheet(address: place.point.address, editing: place) { name, kind in
                        try await store.save(SavedPlace(
                            id: place.id, name: name, kind: kind,
                            point: place.point, pinned: place.pinned))
                    }
                }
                .sheet(item: $editingTemplate) { template in
                    ParcelTemplateEditor(template: template) { try await store.save($0) }
                }
                .sheet(isPresented: $isAddingTemplate) {
                    ParcelTemplateEditor { try await store.save($0) }
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
