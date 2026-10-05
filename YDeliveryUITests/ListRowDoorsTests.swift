import XCTest

/// Two buttons in one `List` row must each open their own target: with the
/// automatic style the row is the hit target and one tap fires every button in
/// it, so «Add from library» opened the item editor and its dialog never drew
/// (owner, 2026-10-05). The route card's action row is the precedent that was
/// already borderless — asserted here too so it stays that way.
final class ListRowDoorsTests: XCTestCase {
    @MainActor
    func testEachDoorInASharedRowOpensItsOwnTarget() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-three-stop-draft", "--uitest-templates"]
        app.launch()

        // The route card's action row (three stops → «Add stop» and «Reorder»):
        // «Reorder» flips its own label and adds no stop.
        let reorder = app.buttons["Reorder"].firstMatch
        XCTAssertTrue(reorder.waitForExistence(timeout: 10))
        reorder.tap()
        let doneReordering = app.buttons["Done reordering"].firstMatch
        XCTAssertTrue(doneReordering.waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", "Where to deliver?"))
                .firstMatch.exists,
            "«Reorder» added a stop — the row fired its neighbour")
        doneReordering.tap()

        // «Add from library» sits below the fold with the item rows; List realizes
        // rows lazily, so scroll the list until it exists. Its label degrades to
        // «Library» under ViewThatFits — accept either, scoped to the list so the
        // tab bar's «Library» never matches.
        let list = app.collectionViews.firstMatch
        let door = list.buttons.matching(
            NSPredicate(format: "label == %@ OR label == %@", "Add from library", "Library")
        ).firstMatch
        for _ in 0..<14 where !door.waitForExistence(timeout: 1) {
            (list.exists ? list : app).swipeUp()
        }
        XCTAssertTrue(door.waitForExistence(timeout: 10), "the library door never drew")
        door.tap()

        // The dialog, not the editor. A confirmationDialog may present as a sheet
        // or a popover — sheet first, app-wide button as the fallback.
        let sheetChoice = app.sheets.buttons["Папка с документами"].firstMatch
        let anyChoice = app.buttons["Папка с документами"].firstMatch
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
