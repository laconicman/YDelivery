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

    /// The window a scheduled pickup may fall in, for the class that will carry it.
    ///
    /// Two sources disagree and neither has been measured. The design handoff (§4) says an
    /// hour ahead to thirty days out; the API document says 30–240 minutes for `express`
    /// and five days for `cargo` — and that document is itself read from Yandex's
    /// reference rather than verified on the wire (package TD-21). Where they conflict
    /// this takes the **narrower** reading, because the failure modes are not
    /// symmetrical: offering too little costs a sender some choice, while offering too
    /// much hands them a default the provider will refuse at ordering time, after they
    /// have committed (author, 2026-09-06).
    ///
    /// The lower bound stays at an hour — stricter than the documented thirty minutes, so
    /// safe under either reading. An unknown class gets the tightest ceiling, since a
    /// window that cannot be justified should not be offered.
    static func dueWindow(for tariff: TariffClass? = nil, now: Date = .now) -> ClosedRange<Date> {
        let ceiling: TimeInterval = switch tariff {
        case .cargo: 5 * 24 * 3600
        default: 4 * 3600
        }
        return now.addingTimeInterval(3600)...now.addingTimeInterval(ceiling)
    }

    /// Whether a scheduled time is still one. A draft outlives its compose sheet by
    /// design, so a parked one can outlive its own pickup time — and a `due` in the past
    /// is refused by the provider, which made every quote fail until the sender happened
    /// to reopen the options and reset it (review, PR #21).
    func scheduleHasLapsed(for tariff: TariffClass?, now: Date = .now) -> Bool {
        guard let due else { return false }
        return !Self.dueWindow(for: tariff, now: now).contains(due)
    }

    /// These options as pricing and the editor should read them: a lapsed schedule is no
    /// schedule, which is what it has become. The «When» row says so too, so the change
    /// is visible rather than a quiet correction on the wire.
    func lapsedScheduleCleared(for tariff: TariffClass?, now: Date = .now) -> DeliveryOptions {
        guard scheduleHasLapsed(for: tariff, now: now) else { return self }
        var cleared = self
        cleared.due = nil
        return cleared
    }

    /// What the «Scheduled pickup» switch *means*: on, and this run has a time; off, and
    /// it goes as soon as possible. The switch is a view control but its meaning is a
    /// model decision (R6) — and putting it here is what makes it testable. Turning it on
    /// must write a due rather than only display one, or a schedule saved without
    /// touching the picker departs as an immediate delivery (review, PR #21).
    mutating func setScheduled(_ isScheduled: Bool, within window: ClosedRange<Date>) {
        due = isScheduled ? (due ?? window.lowerBound) : nil
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
