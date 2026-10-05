import SwiftUI

extension Button {
    /// The screen's one standing action — the bordered-prominent capsule at large
    /// size, headline weight, full width (DesignSystem → "Order bar and CTAs").
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
}
