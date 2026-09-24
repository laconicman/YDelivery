import XCTest

/// Visual verification the author asked for by name (2026-09-14): screenshots of the
/// exact layouts under review — the three-stop item journey rows and the stop chooser.
/// PNGs land in /tmp/draft-shots/ for eyeballing beside the .xcresult attachments.
final class DraftScreenshotTests: XCTestCase {
    @MainActor
    func testItemJourneyAndChooserShots() throws {
        continueAfterFailure = false
        // The launch suite leaves the device rotated — a landscape draft squeezes
        // the card into a strip where swipes land on the map and rows never draw.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-three-stop-draft"]
        app.launch()

        let shots = URL(fileURLWithPath: "/tmp/draft-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        func snap(_ name: String) {
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The draft card with three stops.
        // Rows are buttons with combined labels — child staticTexts never match,
        // so every anchor queries any element kind by label containment.
        let firstAddress = app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS %@", "Николоямская")
        ).firstMatch
        XCTAssertTrue(firstAddress.waitForExistence(timeout: 10))
        snap("1-draft-three-stops")

        // The item row lives below the fold; List realizes rows lazily, so scroll
        // until its Button (children combined into one label) exists. The point
        // rows' combined labels also name the item ("picks up Ноутбук…"), so the
        // anchor is the row that *starts* with it — anything looser can resolve
        // to a route row and open the wrong editor entirely.
        let itemRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Ноутбук")
        ).firstMatch
        for _ in 0..<5 where !itemRow.waitForExistence(timeout: 1) { app.swipeUp() }
        XCTAssertTrue(itemRow.waitForExistence(timeout: 3))
        // The row states its own journey in the stops' words (YD-6) — capture it
        // before the editor opens over it.
        snap("1b-draft-item-row-journey")

        // The item editor: journey rows must show whole addresses. The journey row
        // is a NavigationLink — one button, children's labels combined — at the
        // editor's end, so it may need a scroll before it exists at all.
        itemRow.tap()
        let pickupRow = app.buttons.containing(
            NSPredicate(format: "label CONTAINS %@", "Picked up at")
        ).firstMatch
        // The editor is a sheet: two collection views exist once it covers the
        // draft, and `firstMatch` can resolve to the covered one — scroll
        // whichever list is actually hittable (sheet's), else the screen.
        for _ in 0..<6 where !pickupRow.waitForExistence(timeout: 1) {
            let scrollable = app.collectionViews.allElementsBoundByIndex
                .first(where: { $0.isHittable })
            (scrollable ?? app).swipeUp()
        }
        XCTAssertTrue(pickupRow.waitForExistence(timeout: 3))
        snap("2-item-journey-rows")

        // The chooser: full-width rows, the impossible stop disabled with its reason.
        pickupRow.tap()
        XCTAssertTrue(app.staticTexts["Where it boards"].waitForExistence(timeout: 5))
        snap("3-stop-chooser")
    }
}
