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
        // Rows are single buttons with combined labels (status first) — match
        // the button's own label, as DraftScreenshotTests does; `containing`
        // would resolve to the list itself.
        func row(_ statusPrefix: String) -> XCUIElement {
            app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", statusPrefix)
            ).firstMatch
        }
        let liveRow = row("Courier on the way")
        XCTAssertTrue(liveRow.waitForExistence(timeout: 15))
        snap("1-deliveries-list")

        // The finished order's detail — it carries the chat row. A List row's
        // NavigationLink is one cell; tapping the matched text lands on it.
        // The seed's final refresh and the screen's own sync republish the rows
        // around launch; a tap that lands mid-diff is dropped. Let the list
        // settle, then open the row — by coordinate if the element tap is eaten.
        func open(_ element: XCUIElement) {
            sleep(2)
            // The row's centre lands on the addresses — `RouteLine`. Through Kit
            // 0.4.0 its rows carried an unconditional tap gesture that swallowed
            // the touch and the row opened nothing (Kit #27); tapping here is the
            // regression gate.
            element.tap()
            XCTAssertTrue(app.navigationBars["Order"].waitForExistence(timeout: 5))
        }
        let doneRow = row("Delivered")
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
