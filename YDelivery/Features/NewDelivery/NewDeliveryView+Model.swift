import Foundation
import Observation
// SwiftUI supplies `remove(atOffsets:)` / `move(fromOffsets:toOffset:)` — the exact
// semantics `onDelete`/`onMove` hand this model; reimplementing them here would be the
// riskier kind of purity.
import SwiftUI

extension NewDeliveryView {
    /// The flow's draft: the ordered route and what each stop carries. Owned by
    /// `RootView`, one level above the sheet that renders it (R7: one owner, as low as
    /// the lifetime allows) — dismissing the flow parks the draft, because navigation
    /// must never destroy one (Design → "The tab bar goes").
    ///
    /// Invariants this type enforces, so views cannot break them: the route keeps at
    /// least its two founding rows; the first point is the pickup; at most one return
    /// point exists and it stays last (what could not be handed over goes back at the
    /// end of the run); a swap is offered only when it exchanges two filled ends.
    @Observable @MainActor
    final class Model {
        /// One stop of the draft, before it earns a place in an order. Identity is
        /// minted when the sender adds the row and is stable for its whole life (R8) —
        /// reordering moves the row, never renames it.
        nonisolated struct Point: Identifiable, Hashable, Sendable {
            let id: UUID
            var role: Role
            var place: PickedPlace?
            var contact: Contact?

            init(role: Role, place: PickedPlace? = nil, contact: Contact? = nil) {
                id = UUID()
                self.role = role
                self.place = place
                self.contact = contact
            }
        }

        /// What happens at the door — the sender's vocabulary (забрать · доставить ·
        /// вернуть), mapped to the wire's point types only at the controller boundary.
        nonisolated enum Role: Hashable, Sendable {
            case pickup
            case dropoff
            case `return`
        }

        private(set) var points: [Point]

        init() {
            points = [Point(role: .pickup), Point(role: .dropoff)]
        }

        /// Every stop chosen, nothing pending — the gate for everything downstream
        /// (estimate, offers, creation). An added-but-empty stop is a hole in the
        /// route, not an extra.
        var isRouteComplete: Bool {
            points.count >= 2 && points.allSatisfy { $0.place != nil }
        }

        /// Swapping is the two-point affordance: with more points the order is edited by
        /// reordering, and with an end empty a swap would just *move* the address, which
        /// reads as data loss.
        var canSwap: Bool {
            points.count == 2 && isRouteComplete
        }

        /// From three points on, reordering replaces swapping (board `2b`).
        var canReorder: Bool {
            points.count > 2
        }

        var hasReturnPoint: Bool {
            points.contains { $0.role == .return }
        }

        func point(withID id: Point.ID) -> Point? {
            points.first { $0.id == id }
        }

        /// Roles a stop may switch to. The first row is the route's start and never
        /// changes; the return role is offered while no return point exists — and never
        /// to the route's only delivery, because a route that delivers nothing is not a
        /// route (review, PR #17); a return point may step back to being a delivery.
        func availableRoles(for id: Point.ID) -> [Role] {
            guard let index = points.firstIndex(where: { $0.id == id }), index > 0 else {
                return []
            }
            switch points[index].role {
            case .pickup: return [.dropoff]
            case .dropoff: return hasReturnPoint || dropoffCount < 2 ? [] : [.return]
            case .return: return [.dropoff]
            }
        }

        private var dropoffCount: Int {
            points.count { $0.role == .dropoff }
        }

        /// Exchanges what stands at the two ends — places and the people at the door.
        /// Roles and row identities stay put: the route still starts with a pickup, and
        /// SwiftUI sees the same rows with exchanged content, not new rows.
        func swapEnds() {
            guard canSwap else { return }
            var first = points[0]
            var second = points[1]
            (first.place, second.place) = (second.place, first.place)
            (first.contact, second.contact) = (second.contact, first.contact)
            points[0] = first
            points[1] = second
        }

        /// Adds an unfilled drop-off and returns its id so the caller can open the
        /// picker for it in the same gesture. New stops join before any return point —
        /// the return stays last.
        @discardableResult
        func addStop() -> Point.ID {
            let stop = Point(role: .dropoff)
            let index = points.firstIndex { $0.role == .return } ?? points.endIndex
            points.insert(stop, at: index)
            return stop.id
        }

        /// Removes stops. The pickup row is the route's start and stays; the route never
        /// shrinks below two rows — an A→B draft with a row missing is not a route —
        /// and the last delivery cannot be removed out from beside a return point
        /// (review, PR #17: pickup → return delivers nothing).
        func removePoints(at offsets: IndexSet) {
            guard !offsets.contains(0), points.count - offsets.count >= 2 else { return }
            let remaining = points.indices
                .filter { !offsets.contains($0) }
                .map { points[$0] }
            guard remaining.contains(where: { $0.role == .dropoff }) else { return }
            points = remaining
        }

        /// Reorders stops. The pickup is pinned first and the return last; a move that
        /// would unseat either is clamped rather than half-applied.
        func movePoints(from source: IndexSet, to destination: Int) {
            let lowerBound = 1
            let upperBound = hasReturnPoint ? points.count - 1 : points.count
            guard source.allSatisfy({ $0 >= lowerBound && $0 < upperBound }) else { return }
            let clamped = min(max(destination, lowerBound), upperBound)
            points.move(fromOffsets: source, toOffset: clamped)
        }

        func setPlace(_ place: PickedPlace, for id: Point.ID) {
            guard let index = points.firstIndex(where: { $0.id == id }) else { return }
            points[index].place = place
        }

        /// Stores what ``Contact/storable`` says deserves keeping — an emptied card
        /// returns the row's invitation rather than a blank line.
        func setContact(_ contact: Contact?, for id: Point.ID) {
            guard let index = points.firstIndex(where: { $0.id == id }) else { return }
            points[index].contact = contact.flatMap(\.storable)
        }

        /// Changes what happens at a stop's door. The first row is the route's start and
        /// keeps its pickup role; only one return point may exist, and becoming the
        /// return moves the stop to the end of the run — leaving the role also leaves
        /// the pinned seat.
        func setRole(_ role: Role, for id: Point.ID) {
            guard let index = points.firstIndex(where: { $0.id == id }), index > 0,
                  points[index].role != role
            else { return }
            if role == .return {
                guard !hasReturnPoint else { return }
                points[index].role = role
                points.append(points.remove(at: index))
            } else {
                points[index].role = role
            }
        }
    }
}
