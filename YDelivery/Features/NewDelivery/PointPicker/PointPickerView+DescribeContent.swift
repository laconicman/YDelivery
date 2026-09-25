import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension PointPickerView {
    /// The describe stage — the flow's end, one screen for everything the pin cannot
    /// know: the door details and the person (Round 5, decision #40; author,
    /// 2026-09-14 — setting a point is one flow on one navigation stack, never two
    /// disjoint sheets). Pure presentation: values, bindings, closures.
    struct DescribeContent: View {
        /// The settled address, as the map stage resolved it.
        let addressLine: String
        /// The address names no building — unusual enough for a courier that the
        /// section says so while the point is still being described (author,
        /// 2026-09-18).
        var addressLacksBuilding: Bool = false
        /// Back to the map — the rare, destructive move, so it is a labeled action
        /// here rather than the screen's default (decision #44).
        let changeAddress: () -> Void
        @Binding var parts: AddressParts
        @Binding var contact: Contact
        /// Why keeping this place is unavailable, or `nil` when it is available.
        let saveUnavailableReason: String?
        let bookmark: () -> Void
        let save: () -> Void

        var body: some View {
            Form {
                Section {
                    Text(addressLine) // user data, never a localization key
                    Button(action: changeAddress) {
                        Label("Change the address", systemSymbol: .map)
                    }
                } header: {
                    Text("Address")
                } footer: {
                    if addressLacksBuilding {
                        Text("No building number — the courier may have trouble finding the door.")
                    }
                }

                Section {
                    PartsFields(parts: $parts)
                } header: {
                    Text("Door details")
                } footer: {
                    Text("Building, entrance, floor, apartment, intercom — what the pin can't know.")
                }

                Section {
                    // Explicit components, concatenated only by the name formatter
                    // (author's standing preference); each field autofills from its
                    // own content type.
                    TextField("Given name", text: $contact.givenName)
                        .textContentType(.givenName)
                    TextField("Family name", text: $contact.familyName)
                        .textContentType(.familyName)
                    PhoneField(text: $contact.phone)
                    // No `textContentType`: UIKit has none for a dial extension.
                    TextField("Extension", text: $contact.phoneExtension)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Who's at the door")
                } footer: {
                    // The hint states the bound without blocking: a point may be kept
                    // half-typed, and ordering's blockers say the rest.
                    if !contact.phone.isEmpty, PhoneFormat.dialable(contact.phone) == nil {
                        Text("This isn't a dialable number yet — the courier calls it on arrival.")
                    } else {
                        // Steering, not a gate (author, 2026-09-18): prices need only
                        // the address, so someone pricing options may skip this — but
                        // filling it early is welcome; ordering asks for it.
                        Text("Only the order asks who's at the door — prices don't. The courier calls this number on arrival; leave it empty if nobody will be there.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: Layout.Spacing.unit) {
                    HStack(spacing: Layout.Spacing.unit) {
                        Button(action: save) {
                            Text("Save the point")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        // Unavailable renders disabled with its reason, never absent
                        // (DesignSystem → field rule 2).
                        Button(action: bookmark) {
                            Image(systemSymbol: .bookmark)
                                .font(.headline)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(saveUnavailableReason != nil)
                        .accessibilityLabel(Text("Save as a place"))
                        .accessibilityHint(saveUnavailableReason.map(Text.init) ?? Text(""))
                    }
                    if let saveUnavailableReason {
                        Text(saveUnavailableReason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.bar)
            }
        }
    }

    /// The parts of the address the pin cannot know, as compact typed fields — entrance
    /// is text («со двора», «А»), floor and apartment take the number pad, the intercom
    /// code is its own field (DesignSystem → "Field taxonomy"). `building` leads: it is
    /// the address's own sub-designation (строение/корпус), the wire's `building` slot —
    /// the house number itself stays in the resolved address (YD-10).
    struct PartsFields: View {
        @Binding var parts: AddressParts

        var body: some View {
            VStack(alignment: .leading, spacing: Layout.Spacing.chip) {
                HStack(spacing: Layout.Spacing.chip) {
                    partField("bldg.", text: $parts.building)
                    partField("entrance", text: $parts.entrance)
                    partField("floor", text: $parts.floor)
                        .keyboardType(.numberPad)
                }
                HStack(spacing: Layout.Spacing.chip) {
                    partField("apt.", text: $parts.apartment)
                        .keyboardType(.numberPad)
                    partField("intercom", text: $parts.intercom)
                }
            }
            .font(.footnote)
        }

        private func partField(_ prompt: LocalizedStringKey, text: Binding<String>) -> some View {
            TextField(prompt, text: text)
                .padding(.horizontal, Layout.Spacing.cards)
                .padding(.vertical, Layout.Spacing.chip)
                .background(Color(.secondarySystemFill), in: Capsule())
        }
    }
}

#Preview("Describe: fresh point, empty contact") {
    @Previewable @State var parts = AddressParts()
    @Previewable @State var contact = Contact()
    NavigationStack {
        PointPickerView.DescribeContent(
            addressLine: "Москва, ул Москворечье, 6",
            changeAddress: {},
            parts: $parts,
            contact: $contact,
            saveUnavailableReason: nil,
            bookmark: {},
            save: {}
        )
        .navigationTitle("The point")
    }
}

#Preview("Describe: editing, storage unavailable") {
    @Previewable @State var parts = AddressParts(entrance: "А", floor: "3", apartment: "301")
    @Previewable @State var contact = Contact(
        givenName: "Иван", familyName: "Петров", phone: "+7 912 345-67-89"
    )
    NavigationStack {
        PointPickerView.DescribeContent(
            addressLine: "Москва, Красная площадь, 1",
            changeAddress: {},
            parts: $parts,
            contact: $contact,
            saveUnavailableReason: "Shared storage is unavailable on this install.",
            bookmark: {},
            save: {}
        )
        .navigationTitle("The point")
    }
}
