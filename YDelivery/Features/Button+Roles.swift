import SFSafeSymbols
import SwiftUI
import YDeliveryKit

extension Button {
    /// The screen's one standing action — the bordered-prominent capsule at large
    /// size, headline weight, full width (DesignSystem → "The gateway").
    ///
    /// A `Button` extension, deliberately not a named `ButtonStyle`: styles cannot
    /// compose — `makeBody` receives only the label — so a custom style that wanted
    /// this capsule would have to redraw it and lose the system's chrome (tint,
    /// disabled dimming, the pressed and glass treatments). The recipe bundles the
    /// modifiers instead, which keeps the platform look *and* gives the idea one
    /// name; per-site padding stays with the site. The first of the role recipes —
    /// YD-39 names the rest.
    func primaryAction() -> some View {
        self
            .font(.headline)
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }

    /// The action that yields to the standing one — the bordered capsule at large
    /// size, full width, no tint fill: «Leave it for now», «Close».
    /// (DesignSystem → "Control roles".)
    func secondaryAction() -> some View {
        self
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.large)
    }

    /// The small action that lives in a section header — footnote words with
    /// their glyph, borderless, never a row: «Sort», «Reorder», «From library».
    /// (DesignSystem → "Control roles".)
    func headerAction() -> some View {
        self
            .font(.footnote)
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)
    }

    /// The gateway while a bound is still out — the bordered capsule at large
    /// size and full width, deliberately not `borderedProminent`: blocked is not
    /// ready, and the two states must read apart with color removed (the blocked
    /// bar's second line names the first next step). Still a button, still a
    /// gateway — the tap scrolls and shakes the bound's row.
    /// (DesignSystem → "The gateway".)
    func blockedAction() -> some View {
        self
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.large)
    }

    /// The card that is itself the verb — a tariff card picks on tap, so the
    /// whole card is the button and plain keeps the card's own chrome.
    /// (DesignSystem → "Control roles" → selectable card.)
    func selectableCard() -> some View {
        self
            .buttonStyle(.plain)
    }
}

/// The row-door recipe: the whole row is the verb — plain words, never tinted —
/// with the trailing `›` saying "this row opens" (DesignSystem → "Control
/// roles", "Lists and rows"). One target, one role per row.
struct RowDoor<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.Spacing.gutter) {
                label()
                Spacer(minLength: Layout.Spacing.unit)
                Image(systemSymbol: .chevronForward)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    List {
        Section {
            Button("Order for ₽1 190") {}
                .primaryAction()
            Button("Leave it for now") {}
                .secondaryAction()
            Button("Check out") {}
                .blockedAction()
        } header: {
            HStack {
                Text("Route")
                Spacer()
                Button(action: {}) {
                    Label("Reorder", systemSymbol: .arrowUpArrowDown)
                }
                .headerAction()
            }
        }
        Section("Selectable card") {
            Button {} label: {
                Label("Express", systemSymbol: .truckBox)
            }
            .selectableCard()
        }
        Section("Row door") {
            RowDoor(action: {}) {
                Label("Delivery options", systemSymbol: .sliderHorizontal3)
            }
        }
    }
}
