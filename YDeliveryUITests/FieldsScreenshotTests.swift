import XCTest

/// «Ваши поля» rendered, not just compiled (board `4b`, and the author's standing
/// verify-visually rule): the seeded schema puts a required field in the draft,
/// a hidden one behind «Add field», and both rows in the Settings editor.
final class FieldsScreenshotTests: XCTestCase {
    @MainActor
    func testFieldSectionAndEditorShots() throws {
        continueAfterFailure = false
        // Same guard: the launch suite ends landscape, and these scrolls assume
        // the portrait card.
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-three-stop-draft", "--uitest-fields"]
        app.launch()

        let shots = URL(fileURLWithPath: "/tmp/field-shots", isDirectory: true)
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        func snap(_ name: String) {
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: shots.appendingPathComponent("\(name).png"))
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        // The required «Заказ» row renders as a text field somewhere below the
        // route card; List realizes rows lazily, so scroll until it exists.
        // Swipe the *list*, not the app — an app-level swipe can land on the map.
        let zakaz = app.textFields.containing(
            NSPredicate(format: "placeholderValue == %@", "Заказ")).firstMatch
        let list = app.collectionViews.firstMatch
        for _ in 0..<14 where !zakaz.waitForExistence(timeout: 1) {
            (list.exists ? list : app).swipeUp()
        }
        XCTAssertTrue(zakaz.waitForExistence(timeout: 3), "the required field never drew")
        snap("1-draft-fields")

        // «Тип груза» waits behind «Add field» — one sheet, then the picker draws.
        let addField = app.buttons["Add field"].firstMatch
        XCTAssertTrue(addField.waitForExistence(timeout: 3))
        addField.tap()
        snap("1b-add-field-menu")
        let choice = app.sheets.buttons["Тип груза"].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        choice.tap()
        // The revealed picker now sits in the section — its label is the name.
        XCTAssertTrue(app.staticTexts["Тип груза"].waitForExistence(timeout: 3))
        snap("2-draft-fields-revealed")

        // The settings side: close the sheet, open the editor, the two rows list.
        app.buttons["Close"].firstMatch.tap()
        app.tabBars.buttons["Settings"].firstMatch.tap()
        app.staticTexts["Your fields"].firstMatch.tap()
        let schemaRow = app.staticTexts["Заказ"].firstMatch
        XCTAssertTrue(schemaRow.waitForExistence(timeout: 5))
        snap("3-settings-fields")
    }
}
