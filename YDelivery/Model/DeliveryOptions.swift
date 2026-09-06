import Foundation

/// How the run should go — the options card of board `3d`. Every bounded field carries
/// its bound as data, so the UI can state it instead of hinting (DesignSystem → "Field
/// taxonomy"): loaders 0–2 and only in the cargo van, thermobag only with a courier, the
/// pickup time inside the provider's window.
nonisolated struct DeliveryOptions: Hashable, Sendable {
    /// «Профи» — search among experienced couriers only.
    var proCourier = false
    /// Door-to-door is the provider's default; the wire speaks in its negation
    /// (`skip_door_to_door`), the app never does.
    var toDoor = true
    /// Courier-class only — the bound the toggle states when it must decline.
    var thermobag = false
    /// Cargo-van only, and at most two — the live API's 409 is the source of truth for
    /// the ceiling (§4), whatever the document says.
    var loaders = 0
    /// When the courier should arrive at the pickup; `nil` means as soon as possible.
    var due: Date?
    /// Free text the courier reads — the one deliberately untyped field.
    var comment = ""

    static let loadersRange = 0...2

    /// The provider's window for a scheduled pickup: from an hour ahead to thirty days
    /// out (§4). Computed at use — a window anchored at creation time would drift.
    static func dueWindow(now: Date = .now) -> ClosedRange<Date> {
        now.addingTimeInterval(3600)...now.addingTimeInterval(30 * 24 * 3600)
    }
}

nonisolated extension DeliveryOptions {
    /// The collapsed row's one line: «pro courier · to the door» (board `3d`). Display
    /// formatting lives here, not in a view body (R5).
    var summary: String {
        var parts: [String] = []
        if proCourier { parts.append(String(localized: "pro courier")) }
        if toDoor { parts.append(String(localized: "to the door")) }
        if thermobag { parts.append(String(localized: "thermal bag")) }
        if loaders > 0 { parts.append(String(localized: "\(loaders) loaders")) }
        return parts.isEmpty ? String(localized: "none") : parts.joined(separator: " · ")
    }

    /// «When» row's line: the scheduled time, or the soonest-possible default.
    var whenSummary: String {
        due?.formatted(date: .abbreviated, time: .shortened)
            ?? String(localized: "as soon as possible")
    }
}
