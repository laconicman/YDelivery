import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension LibraryView {
    /// The library's lists, pure: rows and intents in, layout out. The
    /// segment and the typed filter are presentation state — the rows'
    /// `searchableText` is precomputed at the root's side of the seam, same as
    /// the deliveries list's.
    struct Content: View {
        /// A saved place as a row — the kind's glyph, the name, the address,
        /// who answers the door, the pin mark.
        struct PlaceRow: Identifiable, Hashable, Searchable {
            let id: UUID
            let name: String
            let symbol: SFSymbol
            let pinned: Bool
            let address: String
            /// Who answers the door, folded to one line — `nil` drops it rather
            /// than render an empty one (RoutePoint.contactSummary).
            let contact: String?
            var searchableText: String = ""

            init(place: SavedPlace) {
                id = place.id
                name = place.name
                symbol = place.kind.symbol
                pinned = place.pinned
                address = place.point.address
                contact = place.point.contactSummary
                searchableText = [place.name, place.point.address, place.point.contactSummary]
                    .compactMap { $0 }.joined(separator: " ")
            }
        }

        /// A parcel template as a row — the library's own name plus the items'
        /// summaries («5 pcs · 2 kg · 2 500 ₽» each), so the row reads like the
        /// draft rows the template stamps.
        struct ParcelRow: Identifiable, Hashable, Searchable {
            let id: UUID
            let name: String
            let summary: String
            let pinned: Bool
            var searchableText: String = ""

            init(template: ParcelTemplate) {
                id = template.id
                name = template.name
                pinned = template.pinned
                let items = template.items.map(ParcelItem.init(templateItem:))
                summary = items.map(\.summary).joined(separator: "; ")
                searchableText = [template.name, items.map(\.name).joined(separator: " ")]
                    .joined(separator: " ")
            }
        }

        /// Which list is up — «Places | Parcels» (decision: one Library tab,
        /// segmented; Roadmap's sender's-library section).
        enum Segment { case places, parcels }

        let placeRows: [PlaceRow]
        /// Why places are missing when they are missing for a reason — rendered
        /// instead of the empty state, the deliveries list's rule for history.
        var placesError: String? = nil
        let parcelRows: [ParcelRow]
        var parcelsError: String? = nil

        /// The row intents — the root turns each id into the store's verb.
        var pinPlace: (PlaceRow.ID) -> Void = { _ in }
        var editPlace: (PlaceRow.ID) -> Void = { _ in }
        var deletePlace: (PlaceRow.ID) -> Void = { _ in }
        var pinParcel: (ParcelRow.ID) -> Void = { _ in }
        var editParcel: (ParcelRow.ID) -> Void = { _ in }
        var deleteParcel: (ParcelRow.ID) -> Void = { _ in }
        /// The «+» on the Parcels half — the one place a template is authored
        /// without a draft under it.
        var addParcel: () -> Void = {}

        /// The kind glyph's leading column — wide enough for the widest kind
        /// symbol, so names align under one another.
        private static let glyphColumn: CGFloat = 24

        @State private var segment: Segment = .places
        @State private var searchText = ""

        private var visiblePlaceRows: [PlaceRow] { Self.matching(placeRows, query: searchText) }
        private var visibleParcelRows: [ParcelRow] { Self.matching(parcelRows, query: searchText) }

        /// The typed filter — name, address, contact, item words —
        /// case-insensitive, over the visible segment only.
        static func matching<R: Searchable>(_ rows: [R], query: String) -> [R] {
            let query = query.trimmingCharacters(in: .whitespaces)
            guard !query.isEmpty else { return rows }
            return rows.filter { $0.searchableText.localizedCaseInsensitiveContains(query) }
        }

        var body: some View {
            VStack(spacing: 0) {
                Picker("Library", selection: $segment) {
                    Text("Places").tag(Segment.places)
                    Text("Parcels").tag(Segment.parcels)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Layout.Spacing.edge)
                .padding(.vertical, Layout.Spacing.tight)
                switch segment {
                case .places: placesList
                case .parcels: parcelsList
                }
            }
            .searchable(text: $searchText, prompt: "Name, address or contents")
        }

        private var placesList: some View {
            Group {
                if let placesError {
                    // *Could not look* is not *nothing saved* — same rule as
                    // history's unreadable state.
                    ContentUnavailableView {
                        Label("Places can't be read", systemSymbol: .exclamationmarkTriangle)
                    } description: {
                        Text(placesError)
                    }
                } else if !visiblePlaceRows.isEmpty {
                    List {
                        ForEach(visiblePlaceRows) { row in
                            placeRow(row)
                        }
                        // Curate-only is stated where the list ends — places are
                        // earned in the draft, and the footer says so where a
                        // sender looking for «+» will look.
                        Text("Places are saved from a stop while composing a delivery.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                } else if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("No places yet", systemSymbol: .star)
                    } description: {
                        Text("Star a stop while composing a delivery and it waits here.")
                    }
                }
            }
        }

        private var parcelsList: some View {
            Group {
                if let parcelsError {
                    ContentUnavailableView {
                        Label("Parcels can't be read", systemSymbol: .exclamationmarkTriangle)
                    } description: {
                        Text(parcelsError)
                    }
                } else if !visibleParcelRows.isEmpty {
                    List {
                        ForEach(visibleParcelRows) { row in
                            parcelRow(row)
                        }
                        Text("Templates also come from «Save as a template» while composing.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowSeparator(.hidden)
                    }
                } else if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    ContentUnavailableView {
                        Label("No templates yet", systemSymbol: .shippingbox)
                    } description: {
                        Text("«Save as a template» on a parcel, or add one with «+».")
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addParcel() } label: {
                        Label("New template", systemSymbol: .plus)
                    }
                }
            }
        }

        /// A place as a row — glyph · name · pin; address, then the contact.
        /// The menu carries the three verbs; the delete ask parks the row in
        /// the root's confirm dialog.
        private func placeRow(_ row: PlaceRow) -> some View {
            HStack(alignment: .top, spacing: Layout.Spacing.tight) {
                Image(systemSymbol: row.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.glyphColumn)
                VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                    HStack {
                        Text(row.name)
                        if row.pinned {
                            Image(systemSymbol: .pinFill)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(row.address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let contact = row.contact {
                        Text(contact)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .contextMenu {
                Button { pinPlace(row.id) } label: {
                    Label(row.pinned ? "Unpin" : "Pin",
                          systemSymbol: row.pinned ? .pinSlash : .pin)
                }
                Button { editPlace(row.id) } label: {
                    Label("Edit", systemSymbol: .pencil)
                }
                Button(role: .destructive) { deletePlace(row.id) } label: {
                    Label("Delete", systemSymbol: .trash)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deletePlace(row.id) } label: {
                    Label("Delete", systemSymbol: .trash)
                }
            }
        }

        /// A template as a row — the library name plus the item summary; same
        /// menu shape as the places' half.
        private func parcelRow(_ row: ParcelRow) -> some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.hairline) {
                HStack {
                    Text(row.name)
                    if row.pinned {
                        Image(systemSymbol: .pinFill)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(row.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contextMenu {
                Button { pinParcel(row.id) } label: {
                    Label(row.pinned ? "Unpin" : "Pin",
                          systemSymbol: row.pinned ? .pinSlash : .pin)
                }
                Button { editParcel(row.id) } label: {
                    Label("Edit", systemSymbol: .pencil)
                }
                Button(role: .destructive) { deleteParcel(row.id) } label: {
                    Label("Delete", systemSymbol: .trash)
                }
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { deleteParcel(row.id) } label: {
                    Label("Delete", systemSymbol: .trash)
                }
            }
        }
    }
}

/// The one thing both row types filter on — the root precomputes it so the
/// typed query stays a value comparison.
protocol Searchable {
    var searchableText: String { get }
}

// MARK: - Previews

private let previewPlaces: [LibraryView.Content.PlaceRow] = [
    .init(place: SavedPlace(
        name: "Office", kind: .shop,
        point: RoutePoint(latitude: 55.7517, longitude: 37.6176,
                          address: "Москва, Николоямская улица, 49с1",
                          contactName: "Иван Петров", contactPhone: "+79123456789"),
        pinned: true)),
    .init(place: SavedPlace(
        name: "Home", kind: .home,
        point: RoutePoint(latitude: 55.7601, longitude: 37.6492,
                          address: "Москва, Земляной Вал, 27с2"))),
]

private let previewParcels: [LibraryView.Content.ParcelRow] = [
    .init(template: ParcelTemplate(
        name: "Keyboard", pinned: true,
        items: [ParcelTemplate.Item(name: "Mechanical keyboard", quantity: 1,
                                    weightKg: 0.9, cost: "4500", currency: "RUB",
                                    sizeLengthCm: 45, sizeWidthCm: 15, sizeHeightCm: 3)])),
    .init(template: ParcelTemplate(
        name: "Documents",
        items: [ParcelTemplate.Item(name: "Contract papers", quantity: 1,
                                    weightKg: 0.3, currency: "RUB")])),
]

#Preview("Places") {
    NavigationStack {
        LibraryView.Content(placeRows: previewPlaces, parcelRows: previewParcels)
            .navigationTitle("Library")
    }
}

#Preview("Empty") {
    NavigationStack {
        LibraryView.Content(placeRows: [], parcelRows: [])
            .navigationTitle("Library")
    }
}

#Preview("Unreadable") {
    NavigationStack {
        LibraryView.Content(placeRows: previewPlaces,
                            placesError: "The library store could not be opened.",
                            parcelRows: previewParcels)
            .navigationTitle("Library")
    }
}
