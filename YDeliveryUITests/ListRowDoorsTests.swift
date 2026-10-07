import XCTest

/// One row, one target, one role: the library door is the «What's inside»
/// header's control — a header action, not a bare tinted word in a shared row —
/// and the item rows carry the trailing `›` of a row door (DesignSystem →
/// "Control roles", "Lists and rows"). Reorder lives in the route header now;
/// asserted here so it still toggles only itself.
final class ListRowDoorsTests: XCTestCase {
    @MainActor
    func testEachDoorInASharedRowOpensItsOwnTarget() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-three-stop-draft", "--uitest-templates"]
        app.launch()

        // The blocked gateway names the first bound's step — the seeded draft's
        // third stop has no person, so the bar reads «Check out» plus the step.
        let orderBar = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Check out")).firstMatch
        XCTAssertTrue(orderBar.waitForExistence(timeout: 10))
        XCTAssertTrue(
            orderBar.label.contains("Name the person at stop 3"),
            "the bar must name the first next step — got «\(orderBar.label)»")

        // The route header's «Reorder» flips its own label and adds no stop.
        // Section headers render their controls uppercase, so the element's
        // label is «REORDER» — match case-insensitively.
        let reorder = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "Reorder")).firstMatch
        XCTAssertTrue(reorder.waitForExistence(timeout: 10), "«Reorder» header action never drew")
        reorder.tap()
        let doneReordering = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "Done reordering")).firstMatch
        XCTAssertTrue(doneReordering.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "Where to deliver?"))
                .firstMatch.exists,
            "«Reorder» added a stop — the header fired its neighbour")
        doneReordering.tap()

        // The library door is the section header's control — it lives outside
        // the collection view's element tree, so the query is app-wide (the tab
        // bar says «Library», not «From library» — no clash).
        let list = app.collectionViews.firstMatch
        let door = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "From library")).firstMatch
        // The header only enters the element tree while on screen — and a full
        // swipe jumps it straight past the viewport. Big swipes until its own
        // rows draw, then short drags to ease the header into view.
        let addItem = app.buttons.matching(
            NSPredicate(format: "label ==[c] %@", "Add an item")).firstMatch
        for _ in 0..<14 where !door.waitForExistence(timeout: 1) && !addItem.exists {
            (list.exists ? list : app).swipeUp()
        }
        for _ in 0..<10 where !door.exists {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 90)))
            if door.waitForExistence(timeout: 1) { break }
        }
        XCTAssertTrue(door.waitForExistence(timeout: 10), "the library door never drew")
        XCTAssertTrue(door.isHittable, "the library door drew but is not hittable")
        door.tap()

        // The dialog, not the editor. A confirmationDialog may present as a
        // sheet or plain buttons — and renders its rows uppercase, like the
        // section headers.
        let chipQuery = NSPredicate(format: "label ==[c] %@", "Папка с документами")
        let sheetChoice = app.sheets.buttons.matching(chipQuery).firstMatch
        let anyChoice = app.buttons.matching(chipQuery).firstMatch
        let choiceWait = Date.now.addingTimeInterval(10)
        while Date.now < choiceWait, !sheetChoice.exists, !anyChoice.exists {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertFalse(app.navigationBars["Item"].exists,
                       "«Add an item» fired from the library door's tap")
        let choice = sheetChoice.exists ? sheetChoice : anyChoice
        XCTAssertTrue(choice.exists, "the library dialog never opened")

        // Choosing the template appends it as an item row.
        choice.tap()
        let newRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Папка с документами")
        ).firstMatch
        XCTAssertTrue(newRow.waitForExistence(timeout: 10), "the template did not land as an item")
    }
}
