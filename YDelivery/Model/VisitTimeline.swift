import Foundation
import YDeliveryKit

/// The callout's mini-timeline, as data (board `4a`): «Забрал на Москворечье 9:12»,
/// «Едет сюда сейчас», «Вручение ~9:41» — derived from the route's per-stop `visit`
/// records so the rows are testable without a view, and the card never recomputes
/// them (R5).
nonisolated enum VisitTimeline {
    /// One row: its mark position on the route's progress, the fact it states,
    /// and the stamp it speaks — actual for what happened, the provider's
    /// estimate for what has not.
    struct Entry: Hashable, Sendable {
        /// Past facts draw filled, the live state accented, expectation a ring —
        /// chrome, never meaning: the words carry it (DesignSystem's badge rule).
        enum Mark: Hashable, Sendable {
            case past
            case current
            case next
        }

        /// What the row claims, kept semantic so tests pin meaning rather than words.
        enum Fact: Hashable, Sendable {
            /// An earlier stop completed — the courier's progress toward this one.
            /// `pickup` is the first stop's verb; the rest hand over.
            case priorVisit(pickup: Bool, address: String)
            /// This stop's own handover is done.
            case visitedHere(pickup: Bool)
            /// The courier stands at this stop right now.
            case arrived
            /// This stop is the courier's next call — something upstream already
            /// happened, so «heading here» is a fact, not a guess.
            case enRoute
            /// Still waiting, and nothing upstream has happened yet.
            case pending
            /// The courier passed this stop by — the wire's terminal verdict on it.
            case skipped
            /// The provider's own estimate while the stop waits.
            case expected
        }

        var mark: Mark
        var fact: Fact
        var time: Date?
    }

    /// The selected stop's timeline: the last completed stop upstream as context,
    /// this stop's own state, and its estimate while it still waits. A point the
    /// provider never reported on reads `pending` — absent is the honest word for
    /// a stop nobody has reached, on drafts and pre-`visit` rows alike.
    static func entries(route: [RoutePoint], selected index: Int) -> [Entry] {
        guard route.indices.contains(index) else { return [] }
        let point = route[index]
        var entries: [Entry] = []

        if index > 0,
           let priorIndex = route[..<index].lastIndex(where: { $0.visit?.status == .visited }),
           let prior = route[priorIndex].visit {
            entries.append(Entry(
                mark: .past,
                fact: .priorVisit(
                    pickup: priorIndex == 0,
                    address: route[priorIndex].compactAddress
                ),
                time: prior.visitedAt
            ))
        }

        switch point.visit?.status {
        case .visited:
            entries.append(Entry(
                mark: .past,
                fact: .visitedHere(pickup: index == 0),
                time: point.visit?.visitedAt
            ))
        case .arrived:
            entries.append(Entry(
                mark: .current, fact: .arrived,
                time: point.visit?.visitedAt
            ))
        case .skipped:
            entries.append(Entry(
                mark: .past, fact: .skipped,
                time: point.visit?.visitedAt
            ))
        case .pending, nil:
            // «Едет сюда» only when this stop is the courier's next call — every
            // earlier stop settled (visited or passed). A stop behind an
            // unvisited one waits: the courier is heading *there*, not here
            // (review, PR #45).
            let upstream = route[..<index]
            let nextCall = !upstream.isEmpty && upstream.allSatisfy {
                $0.visit?.status == .visited || $0.visit?.status == .skipped
            }
            entries.append(Entry(
                mark: .current,
                fact: nextCall ? .enRoute : .pending,
                time: nil
            ))
        }

        // «expected» belongs to a stop still waiting — the wire fills it only on
        // unvisited points, and a finished stop's estimate would only lie.
        if let expected = point.visit?.expectedAt,
           point.visit?.status == .pending || point.visit?.status == .arrived {
            entries.append(Entry(mark: .next, fact: .expected, time: expected))
        }
        return entries
    }
}
