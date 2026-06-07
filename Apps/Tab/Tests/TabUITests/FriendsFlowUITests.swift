import XCTest

@MainActor
final class FriendsFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTripsAddExpenseOpensPeopleFirstPicker() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["trips.addButton"].waitForExistence(timeout: 5))

        let fab = app.buttons["trips.addExpenseButton"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(fab))
        fab.tap()

        XCTAssertTrue(app.navigationBars["New expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newExpense.groupMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["newExpense.searchField"].waitForExistence(timeout: 5))
    }

    /// People-first global add: from Friends, add an expense with someone by email
    /// (no trip), then confirm the friend + balance appear and the friend-detail
    /// screen breaks the balance out by source.
    func testPeopleFirstNonGroupExpenseCreatesFriendAndDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_SKIP_PUSH_PROMPT"] = "1"
        app.launchEnvironment["TAB_START_TAB"] = "friends"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()

        // Unique counterpart so reruns don't collide in the persisted store.
        let suffix = String((0..<6).map { _ in "abcdefghijklmnopqrstuvwxyz".randomElement()! })
        let email = "uitest\(suffix)@tab.local"
        let friendName = "Uitest\(suffix)"

        XCTAssertTrue(app.staticTexts["Friends"].waitForExistence(timeout: 8))

        let fab = app.buttons["friends.addButton"]
        XCTAssertTrue(fab.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(fab))
        fab.tap()

        // People-first picker: enter an email and invite them.
        let search = app.textFields["newExpense.searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        replaceText(in: search, with: email)

        let invite = app.buttons["newExpense.inviteButton"]
        XCTAssertTrue(invite.waitForExistence(timeout: 5))
        invite.tap()

        app.navigationBars["New expense"].buttons["Next"].tap()

        // Expense form, scoped to the resolved non-group container.
        let amount = app.textFields["expense.amountField"]
        XCTAssertTrue(amount.waitForExistence(timeout: 8))
        replaceText(in: amount, with: "20")
        replaceText(in: app.textFields["expense.descriptionField"], with: "Tapas")
        app.navigationBars["New expense"].buttons["Save"].tap()

        // Back on Friends, the new counterpart now owes the current user.
        // The row is a Button, so its child Texts collapse into the button label.
        let friendRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", friendName)
        ).firstMatch
        XCTAssertTrue(friendRow.waitForExistence(timeout: 8), "new non-group friend should appear on Friends")
        // The row label also proves the balance (the counterpart owes the current user).
        XCTAssertTrue(friendRow.label.localizedCaseInsensitiveContains("owes you"))
        friendRow.tap()

        // Friend detail breaks the balance out by source (the non-group context).
        // SectionHeaderText renders titles uppercased.
        XCTAssertTrue(app.staticTexts["BALANCE BY SOURCE"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Non-group")).firstMatch.exists,
            "friend detail should list the non-group source"
        )
    }

    // MARK: - Helpers

    private func replaceText(in element: XCUIElement, with text: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let current = (element.value as? String) ?? ""
        if !current.isEmpty, current != element.placeholderValue {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        element.typeText(text)
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return element.isHittable
    }
}
