import Foundation
import Testing
import YDeliveryKit
@testable import YDelivery

/// The callout's mini-timeline as a derivation (board `4a`): the rows are facts
/// from the route's `visit` records, so the tests pin *which* rows appear for each
/// constellation — words and marks are the view's job.
@Suite("Visit timeline derivation")
struct VisitTimelineTests {
    private let visitedAt = Date(timeIntervalSince1970: 1_800_001_200)
    private let expectedAt = Date(timeIntervalSince1970: 1_800_002_400)

    private func point(
        _ status: RoutePoint.PointVisitStatus?,
        visitedAt: Date? = nil,
        expectedAt: Date? = nil,
        address: String = "Москва, ул Москворечье, 6"
    ) -> RoutePoint {
        RoutePoint(
            latitude: 55, longitude: 37, address: address,
            visit: status.map {
                .init(status: $0, visitedAt: visitedAt, expectedAt: expectedAt)
            }
        )
    }

    @Test("The destination's card tells the whole leg — pickup done, en route, expected")
    func destinationReadsTheLeg() {
        let route = [
            point(.visited, visitedAt: visitedAt),
            point(.pending, expectedAt: expectedAt, address: "Москва, Каширское шоссе, 52"),
        ]
        let entries = VisitTimeline.entries(route: route, selected: 1)
        #expect(entries.map(\.fact) == [
            .priorVisit(pickup: true, address: "ул Москворечье, 6"),
            .enRoute,
            .expected,
        ])
        #expect(entries.map(\.mark) == [.past, .current, .next])
        #expect(entries[0].time == visitedAt)
        #expect(entries[2].time == expectedAt)
    }

    @Test("The pickup's own card has no upstream context — it is the first stop")
    func firstStopHasNoPriorRow() {
        let route = [point(.visited, visitedAt: visitedAt), point(.pending)]
        let entries = VisitTimeline.entries(route: route, selected: 0)
        #expect(entries.map(\.fact) == [.visitedHere(pickup: true)])
        #expect(entries[0].time == visitedAt,
                "the actual handover stamp, not the estimate")
    }

    @Test("A pending first stop waits without an en-route claim")
    func pendingFirstStopIsNotEnRoute() {
        // «Heading here now» would lie before the courier has the parcel —
        // en-route is a fact only when something upstream already happened.
        let route = [point(.pending, expectedAt: expectedAt), point(.pending)]
        let entries = VisitTimeline.entries(route: route, selected: 0)
        #expect(entries.map(\.fact) == [.pending, .expected])
    }

    @Test("A stop behind an unvisited one waits — the courier is heading there first")
    func pendingBehindPendingIsNotEnRoute() {
        // The pickup is done, but stop Б still waits: the courier's next call
        // is Б, so В reads «not visited yet», never «heading here» (PR #45).
        let route = [
            point(.visited, visitedAt: visitedAt),
            point(.pending, address: "Москва, Б"),
            point(.pending, expectedAt: expectedAt, address: "Москва, В"),
        ]
        let entries = VisitTimeline.entries(route: route, selected: 2)
        #expect(entries.map(\.fact) == [
            .priorVisit(pickup: true, address: "ул Москворечье, 6"),
            .pending,
            .expected,
        ])
    }

    @Test("A skipped upstream stop still counts as progress")
    func skippedUpstreamStillEnRoutes() {
        // The courier passed stop 0 — the next call is the selected one.
        let route = [point(.skipped), point(.pending, expectedAt: expectedAt)]
        let entries = VisitTimeline.entries(route: route, selected: 1)
        #expect(entries.map(\.fact) == [.enRoute, .expected])
    }

    @Test("A courier at the door reads arrived, not done")
    func arrivedIsCurrentNotPast() {
        let route = [point(.visited, visitedAt: visitedAt), point(.arrived, expectedAt: expectedAt)]
        let entries = VisitTimeline.entries(route: route, selected: 1)
        #expect(entries.map(\.fact) == [
            .priorVisit(pickup: true, address: "ул Москворечье, 6"),
            .arrived,
            .expected,
        ])
    }

    @Test("A visited stop speaks its actual stamp — the estimate would only lie")
    func visitedHidesTheEstimate() {
        let route = [
            point(.visited, visitedAt: visitedAt, expectedAt: expectedAt),
            point(.pending),
        ]
        let entries = VisitTimeline.entries(route: route, selected: 0)
        #expect(entries.map(\.fact) == [.visitedHere(pickup: true)])
    }

    @Test("Skipped is the wire's terminal word on the stop")
    func skippedReadsAsSkipped() {
        let route = [point(.visited, visitedAt: visitedAt), point(.skipped)]
        let entries = VisitTimeline.entries(route: route, selected: 1)
        #expect(entries.map(\.fact).contains(.skipped))
    }

    @Test("A stop with no visit record still answers — pending is honest")
    func absentVisitReadsPending() {
        let route = [point(nil), point(nil)]
        #expect(VisitTimeline.entries(route: route, selected: 1).map(\.fact) == [.pending])
    }

    @Test("The middle stop's context is the nearest completed stop, not every prior")
    func priorContextIsNearestCompleted() {
        let third = Date(timeIntervalSince1970: 1_800_003_000)
        let route = [
            point(.visited, visitedAt: visitedAt, address: "Москва, А"),
            point(.visited, visitedAt: third, address: "Москва, Б"),
            point(.pending, expectedAt: expectedAt, address: "Москва, В"),
        ]
        let entries = VisitTimeline.entries(route: route, selected: 2)
        #expect(entries.first?.fact == .priorVisit(pickup: false, address: "Москва, Б"),
                "the leg's origin is the last completed stop — one row, not a recap")
        #expect(entries.first?.time == third)
    }

    @Test("Out-of-range selection yields no rows — the card only opens for real pins")
    func outOfRangeIsEmpty() {
        #expect(VisitTimeline.entries(route: [point(nil)], selected: 5).isEmpty)
    }
}
