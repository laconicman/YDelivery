import XCTest

/// The Library's rows are doors: a tap on a place opens «Edit the place», a tap
/// on a template opens «Edit template» — before this change nothing in either
/// list answered a tap at all, and the owner found it on the TestFlight build
/// (2026-10-05). PNGs land in /tmp/library-shots/ for eyeballing beside the
/// .xcresult attachments. Labels are English where the code speaks English —
/// CI runs en-US (YD-35).
final class LibraryDoorsTests: XCTestCase {
    @MainActor
    func testLibraryRowsOpenTheirEditors() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-places", "--uitest-templates"]
        app.launch()

        let shots = URL(fileURLWithPath: "/tmp/library-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        func snap(_ name: String) {
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The Places list, seeded with «Склад на Невском».
        let libraryTab = app.tabBars.buttons["Library"].firstMatch
        XCTAssertTrue(libraryTab.waitForExistence(timeout: 10))
        libraryTab.tap()
        let placeRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Склад на Невском")
        ).firstMatch
        XCTAssertTrue(placeRow.waitForExistence(timeout: 10))
        snap("1-places")

        // Tap is the door — the place editor opens over the list.
        placeRow.tap()
        XCTAssertTrue(app.navigationBars["Edit the place"].waitForExistence(timeout: 10))
        snap("2-place-editor")
        app.buttons["Cancel"].firstMatch.tap()

        // The Parcels half opens the same way, into its own editor.
        let parcels = app.segmentedControls.buttons["Parcels"].firstMatch
        XCTAssertTrue(parcels.waitForExistence(timeout: 10))
        parcels.tap()
        let parcelRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Папка с документами")
        ).firstMatch
        XCTAssertTrue(parcelRow.waitForExistence(timeout: 10))
        parcelRow.tap()
        XCTAssertTrue(app.navigationBars["Edit template"].waitForExistence(timeout: 10))
        snap("3-template-editor")
        app.buttons["Cancel"].firstMatch.tap()
    }
}
