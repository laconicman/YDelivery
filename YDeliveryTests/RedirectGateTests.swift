import Foundation
import Testing
@testable import YDelivery

/// The expander's gate rules on every hop before the session contacts it — the
/// judgement is pure, so it is tested here without a network (review, PR #18,
/// the edited short-link ask).
@Suite("Redirect gate")
@MainActor
struct RedirectGateTests {
    private typealias Gate = PointPickerView.Model.RedirectGate

    @Test("A hop that already answers with coordinates is captured, not contacted")
    func capturesReadableTargets() {
        #expect(Gate.verdict(
            for: URL(string: "https://yandex.ru/maps/?pt=30.335429,59.944869")!, hop: 1
        ) == .capture)
        #expect(Gate.verdict(
            for: URL(string: "https://maps.apple.com/?ll=55.7558,37.6173")!, hop: 2
        ) == .capture)
    }

    @Test("An ordinary hop is followed; a provider page without coordinates too")
    func followsOrdinaryHops() {
        #expect(Gate.verdict(for: URL(string: "https://tinyurl.com/abc")!, hop: 1) == .follow)
        // A shortener hopping to another shortener stays in the chain.
        #expect(Gate.verdict(for: URL(string: "https://clck.ru/XYZ")!, hop: 2) == .follow)
    }

    @Test("Schemes the flow must not touch are refused where they stand")
    func refusesForeignSchemes() {
        #expect(Gate.verdict(for: URL(string: "ftp://example.com/x")!, hop: 1) == .refuse)
        #expect(Gate.verdict(for: URL(string: "file:///etc/hosts")!, hop: 1) == .refuse)
    }

    @Test("A chain past its cap is a maze, not a link")
    func refusesBeyondTheCap() {
        let url = URL(string: "https://example.com/next")!
        #expect(Gate.verdict(for: url, hop: Gate.hopCap) == .follow)
        #expect(Gate.verdict(for: url, hop: Gate.hopCap + 1) == .refuse)
    }
}
