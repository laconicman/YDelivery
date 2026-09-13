import Foundation
import Testing
@testable import YDelivery

/// The expander's gate rules on every hop before the session contacts it — the
/// judgement is pure, so it is tested here without a network. Since PR #28's second
/// round, the rule is an allowlist: the gate walks only hosts the grammar itself
/// reads, so "where the expander may go" and "what the parser understands" are one
/// list that cannot drift apart — and where an arbitrary hostname might *resolve*
/// stops mattering at all.
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

    @Test("Provider hops without coordinates yet are followed — the chain stays on the map")
    func followsProviderHops() {
        // A provider short link mid-chain: recognized host, no coordinates yet.
        #expect(Gate.verdict(for: URL(string: "https://yandex.ru/maps/-/CHFsZB2l")!, hop: 1) == .follow)
        #expect(Gate.verdict(for: URL(string: "https://go.2gis.com/abc123")!, hop: 2) == .follow)
    }

    @Test("Hosts the grammar does not read are refused — resolution never enters into it")
    func refusesForeignHosts() {
        for target in [
            "https://tinyurl.com/abc",          // generic shortener: not this grammar's
            "https://10.0.0.1/x",               // private literal: not a provider either
            "https://localhost/x",
            "https://fdroid.org/x",             // hostname starting 'fd' — a *name*, not an IPv6 literal
            "ftp://yandex.ru/x",                // provider host, foreign scheme
        ] {
            #expect(Gate.verdict(for: URL(string: target)!, hop: 1) == .refuse, "\(target)")
        }
    }

    @Test("A chain past its cap is a maze, not a link")
    func refusesBeyondTheCap() {
        let url = URL(string: "https://yandex.ru/maps/-/next")!
        #expect(Gate.verdict(for: url, hop: Gate.hopCap) == .follow)
        #expect(Gate.verdict(for: url, hop: Gate.hopCap + 1) == .refuse)
    }

    @Test("The gate and the parser consult one host list")
    func gateMatchesParserHosts() {
        // Every source the grammar reads has its hosts admitted; the sample covers
        // each provider family once.
        for host in ["yandex.ru", "maps.yandex.ru", "yandex.com", "maps.app.goo.gl",
                     "goo.gl", "www.google.com", "2gis.ru", "go.2gis.com", "maps.apple.com"] {
            #expect(MapLink.isProviderHost(host), "\(host)")
        }
        for host in ["notyandex.ru", "yandex.ru.evil.example", "fcbarcelona.com", "tinyurl.com"] {
            #expect(!MapLink.isProviderHost(host), "\(host)")
        }
    }
}
