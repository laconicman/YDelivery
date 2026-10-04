import XCTest

/// After a `--ckschema-seed` run the sender's real list must show no seed row —
/// the seed writes an isolated store under Application Support, not the App
/// Group database this unflagged launch renders.
final class SeedIsolationCheckTests: XCTestCase {

    @MainActor
    func testNoSeedOrderInRealList() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        sleep(4)
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "schema seed")
            ).firstMatch.exists,
            "a seed row leaked into the real store")
    }
}
