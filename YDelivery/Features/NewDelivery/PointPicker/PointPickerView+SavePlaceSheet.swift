import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension PointPickerView {
    /// Keeping a place: a name for the chip and a kind for its glyph. The point itself —
    /// address, parts, coordinates — is already on the refine stage; this sheet only
    /// asks what to call it (the cheap save affordance, author 2026-08-30; the full 3e
    /// editor is a later slice).
    struct SavePlaceSheet: View {
        let address: String
        let save: (String, SavedPlace.Kind) -> Void

        @State private var name = ""
        @State private var kind = SavedPlace.Kind.other
        @Environment(\.dismiss) private var dismiss

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
                }
                .navigationTitle("Save the place")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            save(name, kind)
                            dismiss()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
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

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        PointPickerView.SavePlaceSheet(
            address: "Санкт-Петербург, Невский проспект, 100",
            save: { _, _ in }
        )
    }
}
