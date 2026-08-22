import XCTest

@MainActor
final class BoardFlowUITests: XCTestCase {
    private let app = XCUIApplication()

    func testPairCreateMoveRunStreamCancelAndRelaunch() throws {
        continueAfterFailure = false
        app.launchArguments = ["-board-ui-testing", "-reset-state"]
        app.launch()
        linkServer()

        XCTAssertTrue(element("kanban-board").waitForExistence(timeout: 8))
        XCTAssertTrue(element("server-summary").exists)
        XCTAssertTrue(element("column-backlog").exists)

        createCard()
        moveExistingCard()
        startAndCancelJob()
        proveKeychainPersistence()
    }

    private func linkServer() {
        let serverField = app.textFields["server-url-field"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        serverField.tap()
        serverField.typeText("http://192.168.1.10:8787")

        app.buttons["test-connection-button"].tap()
        XCTAssertTrue(element("connection-success").waitForExistence(timeout: 5))

        let codeField = app.secureTextFields["pair-code-field"]
        codeField.tap()
        let runtimeCode = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8))
        codeField.typeText(runtimeCode)
        app.buttons["pair-button"].tap()
    }

    private func createCard() {
        let addButton = app.buttons["add-card-backlog"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let titleField = app.textFields["new-card-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap()
        titleField.typeText("Verify the iOS board flow")

        let bodyField = app.textFields["new-card-body"]
        bodyField.tap()
        bodyField.typeText("Created by the local board-api mock.")
        app.buttons["confirm-create-card"].tap()

        XCTAssertTrue(app.buttons["card-44"].waitForExistence(timeout: 5))
    }

    private func moveExistingCard() {
        let moveMenu = app.buttons["move-card-42"]
        XCTAssertTrue(moveMenu.waitForExistence(timeout: 5))
        moveMenu.tap()

        let moveToReady = app.buttons["Move to Ready"]
        XCTAssertTrue(moveToReady.waitForExistence(timeout: 3))
        moveToReady.tap()

        let movedCard = app.buttons["card-42"]
        XCTAssertTrue(movedCard.waitForExistence(timeout: 5))
        XCTAssertEqual(movedCard.value as? String, "Ready")
    }

    private func startAndCancelJob() {
        let card = app.buttons["card-44"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()

        let runButton = app.buttons["run-card-button"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        runButton.tap()

        let prompt = app.textViews["job-prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        prompt.tap()
        prompt.typeText("Check the mock runner path.")
        app.buttons["start-job-button"].tap()

        XCTAssertTrue(element("job-log").waitForExistence(timeout: 7))
        let streamedLine = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Starting codex")
        ).firstMatch
        XCTAssertTrue(streamedLine.waitForExistence(timeout: 7))

        let cancelButton = app.buttons["cancel-job-button"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
        XCTAssertTrue(app.staticTexts["Job status: Cancelled"].waitForExistence(timeout: 7))
    }

    private func proveKeychainPersistence() {
        app.terminate()
        app.launchArguments = ["-board-ui-testing"]
        app.launch()

        XCTAssertTrue(element("kanban-board").waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["server-url-field"].exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
