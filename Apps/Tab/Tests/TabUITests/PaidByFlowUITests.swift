import XCTest

@MainActor
final class PaidByFlowUITests: XCTestCase {
    private let currentUserID = "11111111-1111-1111-1111-111111111111"
    private let alexID = "22222222-2222-2222-2222-222222222222"
    private let samID = "33333333-3333-3333-3333-333333333333"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testExactPaidByLedgerSurvivesReturningFromPaidByEditor() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_UI_TEST_SEED_PEOPLE"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Paid By \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        let tripNameField = firstExisting([
            app.textFields["newTrip.nameField"],
            app.textFields["Lisbon weekend"],
        ])
        replaceText(in: tripNameField, with: tripName, app: app)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "100", app: app)
        replaceText(in: app.textFields["expense.descriptionField"], with: "Dinner", app: app)
        app.buttons["expense.paidByRow"].tap()

        XCTAssertTrue(app.navigationBars["Payment & Split"].waitForExistence(timeout: 5))
        app.buttons["paidBy.toggle.\(alexID)"].tap()
        app.buttons["paidBy.toggle.\(samID)"].tap()
        app.buttons["paymentSplit.payerModePill"].tap()
        app.buttons["Exact amounts"].tap()

        let currentUserAmount = app.textFields["paidBy.exactAmount.\(currentUserID)"]
        let alexAmount = app.textFields["paidBy.exactAmount.\(alexID)"]
        let samAmount = app.textFields["paidBy.exactAmount.\(samID)"]
        replaceText(in: currentUserAmount, with: "60", app: app)
        XCTAssertEqual(fieldValue(currentUserAmount), "60")
        replaceText(in: alexAmount, with: "30", app: app)
        XCTAssertEqual(fieldValue(alexAmount), "30")
        replaceText(in: samAmount, with: "10", app: app)
        XCTAssertEqual(fieldValue(samAmount), "10")
        XCTAssertEqual(fieldValue(currentUserAmount), "60")
        XCTAssertEqual(fieldValue(alexAmount), "30")
        XCTAssertEqual(fieldValue(samAmount), "10")
        app.navigationBars["Payment & Split"].buttons["Done"].tap()

        let paidBySummary = app.staticTexts["expense.paidBySummary"]
        XCTAssertTrue(paidBySummary.waitForExistence(timeout: 5))
        XCTAssertEqual(paidBySummary.label, "3 people")

        app.buttons["expense.paidByRow"].tap()
        XCTAssertTrue(app.textFields["paidBy.exactAmount.\(currentUserID)"].waitForExistence(timeout: 5))
        XCTAssertEqual(fieldValue(app.textFields["paidBy.exactAmount.\(currentUserID)"]), "60.00")
        XCTAssertEqual(fieldValue(app.textFields["paidBy.exactAmount.\(alexID)"]), "30.00")
        XCTAssertEqual(fieldValue(app.textFields["paidBy.exactAmount.\(samID)"]), "10.00")
    }

    func testMockAuthTripSeedsPeopleAndExactAmountTapSelectsExistingValue() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Seeded \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName, app: app)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "100", app: app)
        replaceText(in: app.textFields["expense.descriptionField"], with: "Dinner", app: app)
        app.buttons["expense.paidByRow"].tap()

        XCTAssertTrue(app.navigationBars["Payment & Split"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paidBy.toggle.\(alexID)"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paidBy.toggle.\(samID)"].waitForExistence(timeout: 5))

        app.buttons["split.toggle.\(alexID)"].tap()
        app.buttons["paymentSplit.splitModePill"].tap()
        app.buttons["Exact amounts"].tap()

        let currentUserSplit = app.textFields["split.exactAmount.\(currentUserID)"]
        XCTAssertTrue(currentUserSplit.waitForExistence(timeout: 5))
        currentUserSplit.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        currentUserSplit.typeText("40")
        XCTAssertEqual(fieldValue(currentUserSplit), "40")
    }

    func testEditExpenseFromDetailOpensEditForm() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_UI_TEST_SEED_PEOPLE"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Edit Flow \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName, app: app)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "24.50", app: app)
        replaceText(in: app.textFields["expense.descriptionField"], with: "Lunch", app: app)
        app.navigationBars["New expense"].buttons["Save"].tap()

        let expenseRow = app.staticTexts["Lunch"].firstMatch
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 5))
        expenseRow.tap()

        let actionsButton = app.buttons["expenseDetail.actionsButton"]
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.tap()

        let editButton = app.buttons["expenseDetail.editButton"]
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["expense.descriptionField"].waitForExistence(timeout: 5))
    }

    func testPaymentMethodDropdownSelectionPersistsToDetail() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TAB_MOCK_AUTH"] = "1"
        app.launchEnvironment["TAB_UI_TEST_SEED_PEOPLE"] = "1"
        app.launchArguments.append("-ApplePersistenceIgnoreState")
        app.launchArguments.append("YES")
        app.launch()

        XCTAssertTrue(app.staticTexts["Trips"].waitForExistence(timeout: 8))

        let tripName = "Payment Method \(UUID().uuidString.prefix(8))"
        let addTripButton = app.buttons["trips.addButton"]
        XCTAssertTrue(addTripButton.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntilHittable(addTripButton))
        addTripButton.tap()

        replaceText(in: app.textFields["newTrip.nameField"], with: tripName, app: app)
        app.buttons["newTrip.createButton"].tap()

        let tripRow = app.staticTexts[tripName].firstMatch
        XCTAssertTrue(tripRow.waitForExistence(timeout: 5))
        tripRow.tap()

        let addExpenseButton = app.buttons["trip.addExpenseButton"]
        XCTAssertTrue(addExpenseButton.waitForExistence(timeout: 5))
        addExpenseButton.tap()

        replaceText(in: app.textFields["expense.amountField"], with: "18.25", app: app)
        replaceText(in: app.textFields["expense.descriptionField"], with: "Coffee", app: app)

        let paymentMethodMenu = app.buttons["expense.paymentMethodMenu"]
        XCTAssertTrue(paymentMethodMenu.waitForExistence(timeout: 5))
        XCTAssertEqual(paymentMethodMenu.label, "Card")
        paymentMethodMenu.tap()
        app.buttons["Cash"].tap()
        XCTAssertEqual(paymentMethodMenu.label, "Cash")

        app.navigationBars["New expense"].buttons["Save"].tap()

        let expenseRow = app.staticTexts["Coffee"].firstMatch
        XCTAssertTrue(expenseRow.waitForExistence(timeout: 5))
        expenseRow.tap()

        XCTAssertTrue(app.staticTexts["Paid via"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cash"].waitForExistence(timeout: 5))
    }

    private func replaceText(in element: XCUIElement, with text: String, app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        let current = fieldValue(element)
        if !current.isEmpty {
            if let deleteKey = firstExistingIfPresent([
                app.keys["delete"],
                app.keys["Delete"],
                app.buttons["delete"],
                app.buttons["Delete"],
            ], timeout: 1) {
                for _ in current {
                    deleteKey.tap()
                }
            } else {
                element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
        }
        element.typeText(text)
    }

    private func fieldValue(_ element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    private func firstExisting(_ elements: [XCUIElement], timeout: TimeInterval = 5) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = elements.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("No matching element appeared")
        return elements[0]
    }

    private func firstExistingIfPresent(
        _ elements: [XCUIElement],
        timeout: TimeInterval
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let element = elements.first(where: { $0.exists }) {
                return element
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return elements.first(where: { $0.exists })
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
