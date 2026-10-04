import XCTest

/// The listing's second screenshot — the tariff strip with prices, the shot Vision's
/// "Screenshots, in order" asks for and the seeded flags alone could not render
/// (`docs/agent-tasks/screenshot-and-ux-pass.md` flagged the missing seed).
/// `--uitest-offers` answers the draft's fetch from `Offer.listingStrip`; PNGs land
/// in /tmp/listing-shots/ beside the .xcresult attachments, like its siblings.
///
/// A screenshot-production tool, not a regression test — it waits on animation
/// timing and fixture wording, so CI must not depend on it. Run on demand with
/// `YD_LISTING_SHOTS=1` on the test environment — from the CLI, XCTest's
/// `TEST_RUNNER_` prefix forwards it: `TEST_RUNNER_YD_LISTING_SHOTS=1 xcodebuild test …`.
final class ListingStripScreenshotTests: XCTestCase {
    @MainActor
    func testPricedStripShot() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["YD_LISTING_SHOTS"] == "1",
            "listing screenshot tool — run on demand with YD_LISTING_SHOTS=1")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-three-stop-draft", "--uitest-offers"]
        app.launch()

        let shots = URL(fileURLWithPath: "/tmp/listing-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        func snap(_ name: String) {
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The draft opens composing with the priced order button already answering —
        // that first frame doubles as the listing's draft-over-map shot.
        let firstStop = app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS %@", "Николоямская")
        ).firstMatch
        XCTAssertTrue(firstStop.waitForExistence(timeout: 15))
        let pricedCTA = app.buttons.containing(
            NSPredicate(format: "label CONTAINS '₽' OR label CONTAINS 'RUB'")
        ).firstMatch
        XCTAssertTrue(pricedCTA.waitForExistence(timeout: 15),
                      "the priced CTA must render before the first shot")
        snap("0-draft-map-priced")

        // The strip lives below the stops; item summaries carry ₽ too, so the anchor
        // is the conditional class's card button — nothing else on the screen says
        // the wire name (the card labels itself «Super-express» once TariffClass
        // names the class, #111). A containing() query over .any resolves to the
        // window (its subtree contains everything), so the frame source must be
        // the button itself.
        let fasterCard = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "superexpress_d2d")
        ).firstMatch
        let window = app.windows.firstMatch
        for _ in 0..<10 {
            if fasterCard.waitForExistence(timeout: 1),
               fasterCard.frame.minY > window.frame.height * 0.2,
               fasterCard.frame.maxY < window.frame.height * 0.8 { break }
            app.swipeUp()
        }
        XCTAssertTrue(fasterCard.waitForExistence(timeout: 5), "the priced strip must render")
        fasterCard.swipeLeft()  // the strip overflows; reveal the fourth card
        sleep(1)
        fasterCard.tap()        // Faster selected → the CTA reprices to it
        sleep(1)
        snap("1-tariff-strip")
    }
}
