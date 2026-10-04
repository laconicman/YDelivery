import XCTest

/// After a `--ckschema-seed` run the sender's real list must show no seed row —
/// the seed writes an isolated store under Application Support, not the App
/// Group database this unflagged launch renders.
///
/// A manual check, not a CI citizen: on a simulator the seed never ran, so a
/// green run there proves nothing — the check can only fail where a seed ran.
/// Recipe: run `--ckschema-seed` on a paired device, then
/// `TEST_RUNNER_YD_SEED_CHECK=1 xcodebuild test -destination 'platform=iOS,id=<udid>'
/// -only-testing:YDeliveryUITests/SeedIsolationCheckTests`.
final class SeedIsolationCheckTests: XCTestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YD_SEED_CHECK"] == "1",
            "device check after a --ckschema-seed run; YD_SEED_CHECK=1"
        )
    }

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
