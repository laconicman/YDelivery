import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension LibraryView {
    /// The place's own sheet — the naming sheet's two questions (name, kind) plus
    /// the describe stage's two (the door details, the person at the door). The
    /// address stays put: a place is its point, and moving it would make it a
    /// different place (task doc ruling, owner 2026-10-05); a describe-only save
    /// also never rewrites the pin's coordinates (YD-27).
    ///
    /// The sheet owns the write rather than firing it at dismissal, so a store
    /// that cannot take the place says so here, with the fields still typed and
    /// Save still available (SavePlaceSheet's discipline, review PR #18).
    struct PlaceEditor: View {
        /// The place being reshaped — `sheet(item:)` identity is the place's own.
        let place: SavedPlace
        /// The async write — the root forwards `StoreController.save`.
        let save: (SavedPlace) async throws -> Void

        @State private var name: String
        @State private var kind: SavedPlace.Kind
        @State private var parts: AddressParts
        @State private var contact: Contact
        /// A write that failed keeps the sheet up with its reason beside the
        /// fields — SavePlaceSheet's discipline.
        @State private var failure: String?
        @State private var isSaving = false
        @Environment(\.dismiss) private var dismiss

        init(place: SavedPlace,
             save: @escaping (SavedPlace) async throws -> Void,
             keepError: String? = nil) {
            self.place = place
            self.save = save
            _name = State(initialValue: place.name)
            _kind = State(initialValue: place.kind)
            _parts = State(initialValue: place.point.addressParts ?? AddressParts())
            _contact = State(initialValue: Contact(at: place.point) ?? Contact())
            _failure = State(initialValue: keepError)
        }

        /// One definition of the name, so what validation accepts and what gets
        /// stored cannot disagree — SavePlaceSheet's `trimmedName` rule.
        private var trimmedName: String {
            name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("Name — “Home”, “Warehouse on Nevsky”", text: $name)
                        Picker("Kind", selection: $kind) {
                            ForEach(SavedPlace.Kind.allCases, id: \.self) { kind in
                                Label(kind.words, systemSymbol: kind.symbol).tag(kind)
                            }
                        }
                    } header: {
                        Text("Library entry")
                    }

                    Section {
                        Text(addressLine) // user data, never a localization key
                    } header: {
                        Text("Address")
                    } footer: {
                        Text("The address is what makes it this place — to move it, add a new place.")
                    }

                    PointPickerView.DoorDetailsSection(parts: $parts)

                    PointPickerView.ContactSection(contact: $contact) {
                        Text("The courier calls this number on arrival — leave it empty if nobody will be there.")
                    }

                    if let failure {
                        Section {
                            Notice(.error, failure)
                                .font(.footnote)
                        }
                    }
                }
                .navigationTitle("Edit the place")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .disabled(isSaving)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Save", action: saveAndDismiss)
                                .disabled(trimmedName.isEmpty)
                        }
                    }
                }
            }
        }

        /// The address as the row shows it — the coordinates stand in for a pin
        /// that never resolved one.
        private var addressLine: String {
            PickedPlace(place.point).displayAddress
        }

        /// The sheet owns its write: Save awaits the save, dismisses only on
        /// success, and a thrown error stays beside the fields with the sender's
        /// words intact.
        private func saveAndDismiss() {
            isSaving = true
            failure = nil
            let edited = place.edited(name: trimmedName, kind: kind, parts: parts, contact: contact)
            Task {
                do {
                    try await save(edited)
                    dismiss()
                } catch {
                    failure = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

#Preview("Editing") {
    let place = SavedPlace(
        name: "Office", kind: .shop,
        point: RoutePoint(latitude: 55.7517, longitude: 37.6176,
                          address: "Москва, Николоямская улица, 49с1",
                          addressParts: AddressParts(entrance: "А", floor: "3", apartment: "301"),
                          contactName: "Иван Петров",
                          contactGivenName: "Иван", contactFamilyName: "Петров",
                          contactPhone: "+79123456789"),
        pinned: true)
    Color.clear.sheet(isPresented: .constant(true)) {
        LibraryView.PlaceEditor(place: place) { _ in }
    }
}

#Preview("The store could not keep it") {
    let place = SavedPlace(
        name: "Office", kind: .shop,
        point: RoutePoint(latitude: 55.7517, longitude: 37.6176,
                          address: "Москва, Николоямская улица, 49с1"))
    Color.clear.sheet(isPresented: .constant(true)) {
        LibraryView.PlaceEditor(
            place: place,
            save: { _ in throw StoreController.StoreUnavailable() },
            keepError: StoreController.StoreUnavailable().localizedDescription)
    }
}
