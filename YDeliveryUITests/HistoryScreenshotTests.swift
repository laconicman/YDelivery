import XCTest

/// Visual review of the history surfaces: the Deliveries list over a seeded store,
/// one order's detail, and its chat. PNGs land in /tmp/history-shots/ beside the
/// .xcresult attachments — the same arrangement `DraftScreenshotTests` uses.
final class HistoryScreenshotTests: XCTestCase {
    @MainActor
    func testHistoryDetailAndChatShots() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-history"]
        app.launch()

        let shots = URL(fileURLWithPath: "/tmp/history-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        func snap(_ name: String) {
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The list: five rows across the status vocabulary, the live one first.
        // Rows are single buttons with combined labels — match the button's own
        // label, as DraftScreenshotTests does; `containing` would resolve to the
        // list itself. The status pill is its own button inside the row (#62), so
        // rows are matched by the destination address, pills by the status words.
        func row(_ destination: String) -> XCUIElement {
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", destination)
            ).matching(NSPredicate(format: "NOT (label CONTAINS %@)", "Courier on the way")).firstMatch
        }
        let liveRow = row("Каширское шоссе")
        XCTAssertTrue(liveRow.waitForExistence(timeout: 15))
        snap("1-deliveries-list")

        // The status line opens the provider's trail in place (#62): the chip is a
        // borderless button inside the row, so it has its own hit area.
        let statusToggle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Courier on the way")
        ).firstMatch
        XCTAssertTrue(statusToggle.waitForExistence(timeout: 5))
        statusToggle.tap()
        let trailRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "Courier is at the destination door")
        ).firstMatch
        XCTAssertTrue(trailRow.waitForExistence(timeout: 5), "the seeded nine-event trail must render")
        snap("1b-deliveries-row-expanded")
        statusToggle.tap()
        XCTAssertTrue(trailRow.waitForNonExistence(timeout: 5), "the second tap on the pill must collapse the trail")

        // The finished order's detail — it carries the chat row. A List row's
        // NavigationLink is one cell; tapping the matched text lands on it.
        // The seed's final refresh and the screen's own sync republish the rows
        // around launch; a tap that lands mid-diff is dropped. Let the list
        // settle, then open the row — by coordinate if the element tap is eaten.
        func open(_ element: XCUIElement) {
            sleep(2)
            // A row under the compose button or the tab bar is not tappable — bring
            // it into the clear part of the screen first.
            let clearBottom = app.windows.firstMatch.frame.height - 180
            for _ in 0..<6 where element.frame.maxY > clearBottom {
                app.swipeUp(velocity: .slow)
            }
            // Tap the route line (second line of three): the row's vertical centre
            // is the status line, whose tap opens the trail rather than the order
            // (#62), and a tap on the addresses is the regression gate for Kit #27
            // — through 0.4.0 `RouteLine` swallowed exactly that tap.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38)).tap()
            if !app.navigationBars["Order"].waitForExistence(timeout: 5) {
                snap("debug-open-failed")
                XCTFail("row did not open the order")
            }
        }
        let doneRow = row("Арбат")
        XCTAssertTrue(doneRow.waitForExistence(timeout: 5))
        open(doneRow)
        let chatRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Chat")
        ).firstMatch
        for _ in 0..<5 where !chatRow.waitForExistence(timeout: 1) { app.swipeUp() }
        snap("2-order-detail-done")

        XCTAssertTrue(chatRow.waitForExistence(timeout: 3))
        chatRow.tap()
        let confirmation = app.descendants(matching: .any).containing(
            NSPredicate(format: "label CONTAINS %@", "confirmed receipt")
        ).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        snap("3-order-chat")

        // Back out to the live order — the detail with a courier mid-route.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Order"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(liveRow.waitForExistence(timeout: 5))
        open(liveRow)
        snap("4-order-detail-live")
    }
}
