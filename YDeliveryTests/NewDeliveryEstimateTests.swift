import Foundation
import Testing
@testable import YDelivery

/// The estimate's state machine, driven through the injected estimator — offline, like
/// every seam test in this target.
@Suite("Route estimate")
@MainActor
struct NewDeliveryEstimateTests {
    private let office = PickedPlace(latitude: 55.7558, longitude: 37.6173, address: "Офис")
    private let home = PickedPlace(latitude: 55.6460, longitude: 37.6681, address: "Дом")

    private func draft(
        estimator: @escaping NewDeliveryView.Model.RouteEstimator
    ) -> NewDeliveryView.Model {
        let model = NewDeliveryView.Model(estimateRoute: estimator)
        model.setPlace(office, for: model.points[0].id)
        model.setPlace(home, for: model.points[1].id)
        return model
    }

    @Test("A complete route estimates; the result carries distance, time, and the path")
    func completeRouteEstimates() async {
        let estimate = RouteEstimate(
            distanceMeters: 12400,
            travelTime: 2100,
            legs: [[.init(latitude: 55.7558, longitude: 37.6173)]]
        )
        let model = draft { waypoints in
            #expect(waypoints.count == 2, "two stops, one leg request pair")
            return estimate
        }

        await model.calculateEstimate()
        #expect(model.estimate == .ready(estimate))
    }

    @Test("An incomplete route clears to idle — no bar, not a stale number")
    func incompleteRouteIdles() async {
        let model = NewDeliveryView.Model(estimateRoute: { _ in
            Issue.record("nothing to estimate")
            throw Unexpected()
        })
        model.setPlace(office, for: model.points[0].id)

        await model.calculateEstimate()
        #expect(model.estimate == .idle)
        #expect(model.routeWaypoints.isEmpty, "the task id collapses while incomplete")
    }

    @Test("Failure is a rendered state with a retry, never a collapse")
    func failureRenders() async {
        let model = draft { _ in throw Unexpected() }
        await model.calculateEstimate()
        #expect(model.estimate == .failed)
    }

    @Test("The waypoints follow travel order, so reordering re-fires the task id")
    func waypointsFollowTravelOrder() {
        let model = draft { _ in throw Unexpected() }
        let before = model.routeWaypoints
        model.swapEnds()
        let after = model.routeWaypoints

        #expect(before.count == 2 && after.count == 2)
        #expect(before == after.reversed(), "the id change is what cancels the stale run")
    }

    @Test("The summary speaks in kilometres and minutes, not raw meters and seconds")
    func summaryReadsHuman() {
        let estimate = RouteEstimate(distanceMeters: 12400, travelTime: 2100, legs: [])
        let summary = estimate.summary

        #expect(!summary.contains("12400"))
        #expect(!summary.contains("2100"))
        #expect(summary.contains("~"))
    }

    private struct Unexpected: Error {}
}
