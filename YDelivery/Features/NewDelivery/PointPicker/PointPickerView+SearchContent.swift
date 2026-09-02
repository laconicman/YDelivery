import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension PointPickerView {
    /// The picker's home (board `2a`): search first, saved chips above everything, the
    /// map one row away — never a mode. Pure presentation: plain values and bindings in,
    /// intents out; the store and the model stay upstream.
    struct SearchContent: View {
        /// A saved place, reduced to its chip.
        struct Chip: Identifiable, Hashable {
            let id: UUID
            let name: String
            let symbol: SFSymbol
        }

        /// A remembered point, reduced to its row. Identity is the address — the
        /// substrate deduplicates by it upstream (R8: identity from the datum).
        struct Recent: Identifiable, Hashable {
            let address: String
            let detail: String
            var id: String { address }
        }

        let chips: [Chip]
        let recents: [Recent]
        @Binding var searchText: String
        let suggestions: [Model.AddressSuggestion]
        let pasteState: Model.PasteState?
        let isLocating: Bool
        let locationPromptVisible: Bool
        let locationDenied: Bool

        let pickChip: (Chip.ID) -> Void
        let pickRecent: (Recent.ID) -> Void
        let select: (Model.AddressSuggestion) -> Void
        let searchAsAddress: (String) -> Void
        let chooseOnMap: () -> Void
        let useMyLocation: () -> Void
        let continueLocationPrompt: () -> Void
        let dismissLocationPrompt: () -> Void
        let openSettings: () -> Void
        let paste: (String) -> Void
        let placePreviewedPoint: () -> Void
        let fillRoute: (() -> Void)?
        let dismissPaste: () -> Void

        @FocusState private var searchFocused: Bool

        var body: some View {
            List {
                searchField

                if !chips.isEmpty {
                    chipsRow
                }
                if locationPromptVisible {
                    locationPrompt
                }
                if locationDenied {
                    locationDeniedCard
                }
                if let pasteState {
                    PasteCard(
                        state: pasteState,
                        place: placePreviewedPoint,
                        fillRoute: fillRoute,
                        dismiss: dismissPaste
                    )
                }

                if searchText.isEmpty {
                    standingActions
                    if !recents.isEmpty {
                        recentsSection(recents)
                    }
                } else {
                    typingResults
                }
            }
            .listSectionSpacing(.compact)
            .onAppear { searchFocused = true } // the sheet opens on the keyboard
        }

        // MARK: Search field

        private var searchField: some View {
            HStack(spacing: 8) {
                Image(systemSymbol: .magnifyingglass)
                    .foregroundStyle(.secondary)
                TextField("Address or place", text: $searchText)
                    .focused($searchFocused)
                    .textContentType(.fullStreetAddress)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit {
                        if !searchText.isEmpty { searchAsAddress(searchText) }
                    }
                // The paste affordance is an explicit button, never an ambient
                // pasteboard scan (LinkGrammars) — the system control reads the
                // pasteboard only when tapped.
                PasteButton(payloadType: String.self) { strings in
                    if let text = strings.first { paste(text) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }

        private var chipsRow: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        Button {
                            pickChip(chip.id)
                        } label: {
                            Label(chip.name, systemSymbol: chip.symbol)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color(.secondarySystemFill), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            .listRowBackground(Color.clear)
        }

        // MARK: Standing rows

        private var standingActions: some View {
            Section {
                Button(action: useMyLocation) {
                    if isLocating {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Finding where you are…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("My location", systemSymbol: .location)
                    }
                }
                .disabled(isLocating)
                Button(action: chooseOnMap) {
                    Label("Choose on the map", systemSymbol: .plusViewfinder)
                }
            }
        }

        private func recentsSection(_ recents: [Recent]) -> some View {
            Section("Recent") {
                ForEach(recents) { recent in
                    RecentRow(recent: recent, pick: { pickRecent(recent.id) })
                }
            }
        }

        // MARK: Typing

        /// Matching recents pin above the completer's suggestions (decision #7's list
        /// order); when nothing matches at all, the escape hatches take over rather
        /// than a dead end (board `2a`, «Ничего не нашлось»).
        @ViewBuilder
        private var typingResults: some View {
            let matching = Self.matching(recents, query: searchText)
            if matching.isEmpty, suggestions.isEmpty {
                Section {
                    Text("No matches. Try the text as an address, or place the point by hand.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        searchAsAddress(searchText)
                    } label: {
                        Label("Search “\(searchText)” as an address", systemSymbol: .scope)
                    }
                    Button(action: chooseOnMap) {
                        Label("Choose on the map", systemSymbol: .plusViewfinder)
                    }
                }
            } else {
                Section {
                    ForEach(matching) { recent in
                        RecentRow(recent: recent, pick: { pickRecent(recent.id) })
                    }
                    ForEach(suggestions) { suggestion in
                        Button {
                            select(suggestion)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(suggestion.title)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemSymbol: .magnifyingglass)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }

        /// Recents whose address contains the query — pinned above suggestions while
        /// typing. Pure so the ordering rule is testable.
        static func matching(_ recents: [Recent], query: String) -> [Recent] {
            let needle = query.trimmingCharacters(in: .whitespaces)
            guard !needle.isEmpty else { return [] }
            return recents.filter { $0.address.localizedCaseInsensitiveContains(needle) }
        }

        // MARK: Location cards

        private var locationPrompt: some View {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Show where you are?", systemSymbol: .location)
                        .font(.headline)
                    Text("Your position appears on the map and becomes the pickup point. Everything works without it — points can be placed by hand.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Continue", action: continueLocationPrompt)
                            .buttonStyle(.borderedProminent)
                        Button("Not now", action: dismissLocationPrompt)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        }

        private var locationDeniedCard: some View {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Location access is off", systemSymbol: .locationSlash)
                        .font(.headline)
                    Text("Your position can't be shown or used as the pickup point. Everything else works.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Settings", action: openSettings)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Rows

extension PointPickerView.SearchContent {
    /// One remembered point: the clock, the address, the person — never a pin shape,
    /// never a timestamp (decision #10; `2c`'s Recent row).
    struct RecentRow: View {
        let recent: Recent
        let pick: () -> Void

        var body: some View {
            Button(action: pick) {
                Label {
                    VStack(alignment: .leading) {
                        Text(recent.address)
                        if !recent.detail.isEmpty {
                            Text(recent.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemSymbol: .clock)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    /// The paste card: a verifiable point (or route, or an honest failure) — the pin is
    /// always shown before it joins the route, because coordinate order flips per
    /// provider (LinkGrammars, the two traps).
    struct PasteCard: View {
        let state: PointPickerView.Model.PasteState
        let place: () -> Void
        let fillRoute: (() -> Void)?
        let dismiss: () -> Void

        var body: some View {
            Section {
                switch state {
                case .expanding:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Expanding the link…")
                            .foregroundStyle(.secondary)
                    }
                case .resolving:
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Naming the point…")
                            .foregroundStyle(.secondary)
                    }
                case .preview(let point, let source):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Looks like a link with a point — use it?")
                            .font(.subheadline)
                        Text(point.displayAddress)
                            .font(.headline)
                        Text("\(coordinateLine(point)) · \(sourceName(source))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button("Place the point", action: place)
                                .buttonStyle(.borderedProminent)
                            Button("Not now", action: dismiss)
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                case .routePreview(let from, let to, let source):
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A route link — fill both ends?")
                            .font(.subheadline)
                        Label(from.displayAddress, systemSymbol: .smallcircleFilledCircle)
                        Label(to.displayAddress, systemSymbol: .mappinCircleFill)
                        Text(sourceName(source))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            if let fillRoute {
                                Button("Fill both ends", action: fillRoute)
                                    .buttonStyle(.borderedProminent)
                            }
                            Button("Not now", action: dismiss)
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                case .failed(let failure):
                    VStack(alignment: .leading, spacing: 8) {
                        switch failure {
                        case .couldNotExpand(let original):
                            Label("The short link couldn't be expanded", systemSymbol: .wifiSlash)
                                .font(.headline)
                            Text("Open it in the maps app and copy the address — or place the point on the map by hand.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(original.absoluteString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        case .noCoordinates:
                            Text("The link names a place, but carries no point")
                                .font(.headline)
                            Text("That's a listing card — there are no coordinates in the address. Open it and copy the street address instead.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        case .notALink:
                            Text("The pasteboard doesn't look like a map link or coordinates.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Button("Dismiss", action: dismiss)
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        private func coordinateLine(_ place: PickedPlace) -> String {
            PickedPlace(latitude: place.latitude, longitude: place.longitude, address: "").displayAddress
        }

        private func sourceName(_ source: MapLink.Source) -> String {
            switch source {
            case .yandexMaps: String(localized: "from a Yandex Maps link")
            case .googleMaps: String(localized: "from a Google Maps link")
            case .twoGIS: String(localized: "from a 2GIS link")
            case .geoURI: String(localized: "from a geo: link")
            case .appleMaps: String(localized: "from an Apple Maps link")
            case .rawCoordinates: String(localized: "from pasted coordinates")
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty query: chips, actions, recents") {
    @Previewable @State var text = ""
    PointPickerView.SearchContent(
            chips: [
                .init(id: UUID(), name: "Дом", symbol: .house),
                .init(id: UUID(), name: "Склад на Невском", symbol: .building2),
            ],
            recents: [
                .init(address: "Москва, ул Москворечье, 6", detail: "Москва · Иван Петров"),
                .init(address: "Москва, Каширское шоссе, 52", detail: "Москва"),
            ],
            searchText: $text,
            suggestions: [],
            pasteState: nil,
            isLocating: false,
            locationPromptVisible: false,
            locationDenied: false,
            pickChip: { _ in },
            pickRecent: { _ in },
            select: { _ in },
            searchAsAddress: { _ in },
            chooseOnMap: {},
            useMyLocation: {},
            continueLocationPrompt: {},
            dismissLocationPrompt: {},
            openSettings: {},
            paste: { _ in },
            placePreviewedPoint: {},
            fillRoute: nil,
            dismissPaste: {}
        )
}

#Preview("Paste preview card") {
    List {
        PointPickerView.SearchContent.PasteCard(
            state: .preview(
                PickedPlace(latitude: 55.75361, longitude: 37.62094, address: "Москва, Красная площадь, 1"),
                source: .yandexMaps
            ),
            place: {},
            fillRoute: nil,
            dismiss: {}
        )
        PointPickerView.SearchContent.PasteCard(
            state: .failed(.couldNotExpand(original: URL(string: "https://maps.app.goo.gl/Abc123")!)),
            place: {},
            fillRoute: nil,
            dismiss: {}
        )
    }
}

#Preview("Location prompt and denied") {
    @Previewable @State var text = ""
    PointPickerView.SearchContent(
        chips: [],
        recents: [],
        searchText: $text,
        suggestions: [],
        pasteState: nil,
        isLocating: false,
        locationPromptVisible: true,
        locationDenied: true,
        pickChip: { _ in },
        pickRecent: { _ in },
        select: { _ in },
        searchAsAddress: { _ in },
        chooseOnMap: {},
        useMyLocation: {},
        continueLocationPrompt: {},
        dismissLocationPrompt: {},
        openSettings: {},
        paste: { _ in },
        placePreviewedPoint: {},
        fillRoute: nil,
        dismissPaste: {}
    )
}
