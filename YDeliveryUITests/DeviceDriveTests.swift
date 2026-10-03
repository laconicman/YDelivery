import XCTest

/// Drives the *real* app state on a paired device — no `--uitest-*` fixtures: the
/// sender's parked draft, the real store, the real provider session. Written to
/// *see* states the owner reported rather than simulate them: what the review
/// sheet actually blocks on, what the picker's saved chips look like — and, on
/// the owner's explicit invitation, a real claim placed and cancelled inside the
/// free window. Screenshots land as .xcresult attachments; the visible sheet
/// text is also dumped to the test log.
final class DeviceDriveTests: XCTestCase {

    @MainActor
    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Re-enters a text field's contents: tap, then double-tap to select the
    /// word (drafted names and values are single tokens) so typing replaces
    /// rather than appends.
    @MainActor
    private func retype(_ field: XCUIElement, _ text: String) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty {
            field.doubleTap()
        }
        field.typeText(text)
    }

    @MainActor
    private func dump(_ prefix: String, _ app: XCUIApplication) {
        for element in app.staticTexts.allElementsBoundByIndex {
            NSLog("%@ TEXT: %@", prefix, element.label)
        }
        for element in app.buttons.allElementsBoundByIndex where element.isHittable {
            NSLog("%@ BUTTON: %@ enabled=%d", prefix, element.label, element.isEnabled)
        }
    }

    /// Compose → the parked draft → Order → the review sheet: which bounds it
    /// lists, and whether the CTA exists. Then a fresh stop's picker for the
    /// saved-place chips. No writes beyond opening screens.
    @MainActor
    func testBlockedReviewSheetAndPicker() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        let compose = app.buttons["New Delivery"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15))
        compose.tap()
        snap("01-draft")

        // The bar only works once an offer is priced and selected — a wire call.
        let orderBar = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Order")).firstMatch
        guard orderBar.waitForExistence(timeout: 60) else {
            snap("02-no-order-bar")
            dump("DRAFT", app)
            XCTFail("The order bar never appeared")
            return
        }
        let priced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: orderBar)
        guard XCTWaiter.wait(for: [priced], timeout: 60) == .completed else {
            snap("02-order-bar-disabled")
            dump("DRAFT", app)
            XCTFail("The order bar never priced")
            return
        }
        snap("02-draft-priced")
        orderBar.tap()

        XCTAssertTrue(app.navigationBars["Review the order"].waitForExistence(timeout: 10))
        snap("03-review-sheet")
        dump("SHEET", app)

        // Back to the draft, then a fresh stop's picker — the chips' home. The
        // Order bar floats over the row's bottom edge — tap its top.
        app.navigationBars.buttons.firstMatch.tap()
        let addStop = app.buttons["Add stop"]
        for _ in 0..<8 where !addStop.isHittable { app.swipeUp() }
        if addStop.waitForExistence(timeout: 5), addStop.isHittable {
            addStop.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            XCTAssertTrue(app.textFields["Address or place"].waitForExistence(timeout: 10))
            snap("04-picker-chips")
            app.buttons["Cancel"].tap()
        }
    }

    /// Unblocks the parked draft for ordering — the bounds the review sheet
    /// named, cleared through the same UI a sender has:
    ///
    /// - «Заказ» and "Schema seed" are fixture litter — `--uitest-fields` and the
    ///   CloudKit schema seed wrote them; both are deleted, which also ships the
    ///   tombstone on sync. «Тип груза» is the sender's own and stays.
    /// - The pickup's *floor* pill carries digits an earlier pass typed into the
    ///   wrong field — cleared before they ride to a courier.
    /// - The third stop carries no contact — the draft is itself uitest fixture
    ///   residue, so a fixture-consistent person fills it.
    /// - The item has a name but no declared value — one is typed in the editor.
    @MainActor
    func testUnblockTheDraft() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        // 1. The field schema. «Заказ» and "Schema seed" are fixture litter —
        // both get deleted, which also ships their tombstones on sync.
        app.tabBars.buttons["Settings"].tap()
        let fieldsLink = app.buttons["Your fields"]
        XCTAssertTrue(fieldsLink.waitForExistence(timeout: 10))
        fieldsLink.tap()
        snap("05-fields")

        for name in ["Заказ", "Schema seed"] {
            let row = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
            if row.waitForExistence(timeout: 5) {
                row.swipeLeft()
                let delete = app.buttons["Delete"]
                if delete.waitForExistence(timeout: 3) { delete.tap() }
            }
        }
        snap("06-fields-clean")

        // 2. Back to the draft.
        app.navigationBars.buttons.firstMatch.tap() // Your fields → Settings
        app.tabBars.buttons["Deliveries"].tap()
        let compose = app.buttons["New Delivery"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15))
        compose.tap()

        // 3a. An earlier pass typed the phone into the pickup's *floor* pill —
        // clear it so no nonsense rides to the courier.
        let pickup = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "+79123456789")).firstMatch
        for _ in 0..<4 where !pickup.isHittable { app.swipeUp() }
        if pickup.waitForExistence(timeout: 5), pickup.isHittable {
            pickup.tap()
            let cont = app.buttons["Continue"]
            if cont.waitForExistence(timeout: 3) { cont.tap() }
            let floor = app.textFields.matching(
                NSPredicate(format: "placeholderValue == %@", "floor")).firstMatch
            if floor.waitForExistence(timeout: 10) {
                floor.tap()
                floor.doubleTap() // selects the word
                floor.typeText("\u{8}") // backspace deletes the selection
            }
            snap("08a-floor-cleared")
            app.buttons["Save the point"].tap()
        }

        // 3b. The third stop's empty contact — the contact row invites it.
        // `.containing` walks ancestors and taps the container's centre, which
        // is how the pickup's row got the first pass's text — query the row's
        // own button instead. And the floating Order bar overlaps the row's
        // bottom, so tap its top edge, not its centre.
        let whoReceives = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Who receives")).firstMatch
        for _ in 0..<8 where !whoReceives.isHittable { app.swipeUp() }
        if whoReceives.waitForExistence(timeout: 5), whoReceives.isHittable {
            whoReceives.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            let cont = app.buttons["Continue"]
            if cont.waitForExistence(timeout: 3) { cont.tap() }
            let given = app.textFields["Given name"]
            XCTAssertTrue(given.waitForExistence(timeout: 10))
            given.tap()
            given.typeText("Иван")
            let family = app.textFields["Family name"]
            family.tap()
            family.typeText("Петров")
            // The phone box's placeholder is the libphonenumber example — the
            // only field whose placeholderValue carries digits.
            let phone = app.textFields.matching(NSPredicate(
                format: "placeholderValue CONTAINS %@", "912")).firstMatch
            if phone.waitForExistence(timeout: 5) {
                phone.tap()
                phone.typeText("9123456789")
            }
            snap("08b-contact-filled")
            app.buttons["Save the point"].tap()
        }

        // 4. The item's declared value — retype so a rerun stays at 500.
        let itemRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Пакет")).firstMatch
        for _ in 0..<4 where !itemRow.isHittable { app.swipeUp() }
        if itemRow.waitForExistence(timeout: 5) {
            itemRow.tap()
            let value = app.textFields["Value"]
            XCTAssertTrue(value.waitForExistence(timeout: 10))
            retype(value, "500")
            snap("09-item-value")
            app.buttons["Save"].tap()
        }
        snap("10-draft-unblocked")
    }

    /// The full loop the owner asked to see: a real claim placed and cancelled
    /// inside the free window. Real money moves between confirm and cancel —
    /// only run intentionally.
    @MainActor
    func testPlaceAndCancelClaim() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launch()

        let compose = app.buttons["New Delivery"]
        XCTAssertTrue(compose.waitForExistence(timeout: 15))
        compose.tap()

        // The provider refused the three-stop run: claim validation says
        // «Для точки назначения 2 нет отправлений» even though offers priced
        // it. The real claim rides the simplest serviceable route — pickup →
        // drop-off — so the middle stop comes out.
        let middle = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Земляной Вал")).firstMatch
        if middle.waitForExistence(timeout: 5) {
            middle.swipeLeft()
            let delete = app.buttons["Delete"]
            if delete.waitForExistence(timeout: 3) {
                delete.tap()
                snap("10-route-simplified")
            }
        }

        // Door-to-door drifted provider-side — the accept refuses «опция
        // изменилась» and Try again resubmits the same stale requirement.
        // Removing it escapes the version loop; it was never a real need here.
        // The row's full label is «Options, to the door» and it is the last
        // list row — the floating Order bar covers all but a sliver of it, so
        // "hittable" is a lie at rest. Keep scrolling until the row's bottom
        // clears the bar's top, then tap inside the exposed part.
        let optionsRow = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Options")).firstMatch
        let orderBar = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Order")).firstMatch
        XCTAssertTrue(orderBar.waitForExistence(timeout: 60))
        var clearOfBar: Bool {
            optionsRow.isHittable && orderBar.exists
                && optionsRow.frame.maxY < orderBar.frame.minY
        }
        for _ in 0..<8 where !clearOfBar { app.swipeUp() }
        if optionsRow.waitForExistence(timeout: 5), clearOfBar {
            optionsRow.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
            let toDoor = app.switches["To the door"]
            let scheduled = app.switches["Scheduled pickup"]
            if toDoor.waitForExistence(timeout: 10) {
                // A centre .tap() lands dead on these controls — the element
                // spans the whole row and the knob sits at its right edge.
                // Aim there; a knob-wards swipe is the fallback.
                NSLog("DRIVE SWITCH value=%@",
                      String(describing: toDoor.value))
                toDoor.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                if (toDoor.value as? NSNumber)?.boolValue ?? true {
                    toDoor.swipeLeft()
                }
                // Future-date the claim: a pickup still hours out keeps the
                // cancel free even if the test never reaches that leg.
                if scheduled.waitForExistence(timeout: 3),
                   ((scheduled.value as? NSNumber)?.boolValue) == false {
                    scheduled.coordinate(
                        withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                    if !((scheduled.value as? NSNumber)?.boolValue ?? false) {
                        scheduled.swipeRight()
                    }
                }
                snap("10-options-door-off")
                NSLog("DRIVE SWITCH after=%@ scheduled=%@",
                      String(describing: toDoor.value),
                      String(describing: scheduled.value))
                app.buttons["Save"].tap()
            } else {
                snap("10-options-not-open")
            }
        } else {
            snap("10-options-row-covered")
        }
        // The bar exists before the offer lands — disabled, a tap dead-ends.
        // Wait for the priced state, when it enables.
        let priced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: orderBar)
        XCTAssertEqual(XCTWaiter.wait(for: [priced], timeout: 60), .completed)
        orderBar.tap()

        XCTAssertTrue(app.navigationBars["Review the order"].waitForExistence(timeout: 10))
        let confirm = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Order for")).firstMatch
        // Ready puts Confirm in the footer's last section — below the fold, so
        // the List has not materialised it yet; scroll the sheet to it.
        for _ in 0..<6 where !confirm.exists { app.swipeUp() }
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        guard confirm.isEnabled else {
            snap("10-still-blocked")
            dump("SHEET", app)
            XCTFail("The review sheet still blocks — run the field cleanup first")
            return
        }
        snap("10-ready-to-confirm")
        confirm.tap()

        // The provider can refuse a freshly-repriced draft («опция изменилась»)
        // — its own instruction is to check the option and order again. One
        // bounded retry honours that; a second failure is real evidence.
        let placed = app.staticTexts["Order placed — finding a courier"]
        if !placed.waitForExistence(timeout: 120) {
            let retry = app.buttons["Try again"]
            if retry.waitForExistence(timeout: 5) {
                snap("11-failed-once")
                retry.tap()
            }
        }
        XCTAssertTrue(placed.waitForExistence(timeout: 120))
        snap("11-placed")
        app.buttons["Done"].tap()

        // The new claim heads "In progress" — the list's first row.
        let firstRow = app.cells.firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 15))
        snap("12-deliveries")
        firstRow.tap()

        let cancel = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Cancel this delivery")).firstMatch
        // Terms arrive over the wire — the ask can take a beat.
        XCTAssertTrue(cancel.waitForExistence(timeout: 30))
        NSLog("DRIVE TERMS: %@", cancel.label)
        snap("13-cancel-terms")
        cancel.tap()

        let confirmCancel = app.sheets.firstMatch.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Cancel this delivery")).firstMatch
        XCTAssertTrue(confirmCancel.waitForExistence(timeout: 5))
        snap("14-cancel-dialog")
        confirmCancel.tap()

        let cancelled = app.staticTexts["Cancelled"]
        XCTAssertTrue(cancelled.waitForExistence(timeout: 60))
        snap("15-cancelled")
    }
}
