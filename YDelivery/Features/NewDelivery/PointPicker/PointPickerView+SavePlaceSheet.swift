import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension PointPickerView {
    /// Keeping a place: a name for the chip and a kind for its glyph. The point itself —
    /// address, parts, coordinates — is already on the refine stage; this sheet only
    /// asks what to call it (the cheap save affordance, author 2026-08-30; the full 3e
    /// editor is a later slice).
    ///
    /// The sheet owns the write rather than firing it at dismissal, so a store that
    /// cannot take the place says so here, with the name still typed and Save still
    /// available (review, PR #18).
    struct SavePlaceSheet: View {
        let address: String
        let save: (String, SavedPlace.Kind) async throws -> Void

        @State private var name = ""
        @State private var kind = SavedPlace.Kind.other
        @State private var isSaving = false
        @State private var failure: String?
        @Environment(\.dismiss) private var dismiss

        /// One definition of the name, so what validation accepts and what gets stored
        /// cannot disagree — a chip labelled “ Дом ” sorts and reads as its own place.
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
                    } footer: {
                        Text(address)
                    }

                    if let failure {
                        Section {
                            Label(failure, systemSymbol: .exclamationmarkTriangle)
                                .foregroundStyle(.secondary)
                        } footer: {
                            Text("The place was not kept. Try again, or close and carry on — the point is still on the map.")
                        }
                    }
                }
                .navigationTitle("Save the place")
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
                            Button("Save", action: attemptSave)
                                .disabled(trimmedName.isEmpty)
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }

        /// Dismissal is the *success* path only. The task is owned by a sheet that stays
        /// presented for its whole life, so it cannot outlive what it reports to.
        private func attemptSave() {
            isSaving = true
            failure = nil
            Task {
                do {
                    try await save(trimmedName, kind)
                    dismiss()
                } catch {
                    failure = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}

extension SavedPlace.Kind {
    /// The chip's glyph. ПВЗ and locker kinds join when the app can send to one.
    var symbol: SFSymbol {
        switch self {
        case .home: .house
        case .warehouse: .building2
        case .shop: .bag
        case .other: .mappinAndEllipse
        }
    }

    var words: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .warehouse: "Warehouse"
        case .shop: "Shop"
        case .other: "Other"
        }
    }
}

#Preview("Naming a place") {
    Color.clear.sheet(isPresented: .constant(true)) {
        PointPickerView.SavePlaceSheet(
            address: "Санкт-Петербург, Невский проспект, 100",
            save: { _, _ in }
        )
    }
}

#Preview("The store could not keep it") {
    Color.clear.sheet(isPresented: .constant(true)) {
        PointPickerView.SavePlaceSheet(
            address: "Санкт-Петербург, Невский проспект, 100",
            save: { _, _ in throw StoreController.StoreUnavailable() }
        )
    }
}
