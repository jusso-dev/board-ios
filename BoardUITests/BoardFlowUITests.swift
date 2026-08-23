import XCTest

@MainActor
final class BoardFlowUITests: XCTestCase {
    private let app = XCUIApplication()

    func testPairCreateMoveRunStreamCancelAndRelaunch() throws {
        continueAfterFailure = false
        app.launchArguments = ["-board-ui-testing", "-reset-state"]
        app.launch()
        linkServer()

        XCTAssertTrue(element("work-overview").waitForExistence(timeout: 8))
        XCTAssertTrue(element("work-overview-summary").exists)
        XCTAssertTrue(element("overview-card-other-org/operations-7").exists)
        XCTAssertTrue(element("server-summary").exists)

        searchAcrossOrganisations()
        XCTAssertTrue(element("kanban-board").waitForExistence(timeout: 5))
        XCTAssertTrue(element("column-backlog").exists)
        createCard()
        moveExistingCard()
        startAndCancelJob()
        proveKeychainPersistence()
    }

    func testForegroundActivationRefreshesAllWork() throws {
        app.launchArguments = ["-board-ui-testing", "-reset-state", "-reveal-card-on-foreground"]
        app.launch()
        linkServer()

        XCTAssertTrue(element("work-overview").waitForExistence(timeout: 8))
        let foregroundCard = element("overview-card-example-user/board-api-99")
        XCTAssertFalse(foregroundCard.exists)

        XCUIDevice.shared.press(.home)
        app.activate()

        XCTAssertTrue(foregroundCard.waitForExistence(timeout: 8))
    }

    func testPullToRefreshLoadsWorkWithoutShowingOffline() throws {
        app.launchArguments = ["-board-ui-testing", "-reset-state", "-reveal-card-on-foreground"]
        app.launch()
        linkServer()

        XCTAssertTrue(element("work-overview").waitForExistence(timeout: 8))
        let refreshedCard = element("overview-card-example-user/board-api-99")
        XCTAssertFalse(refreshedCard.exists)

        let overview = app.collectionViews["work-overview"]
        XCTAssertTrue(overview.waitForExistence(timeout: 5))

        let pullStart = overview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let pullEnd = overview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        pullStart.press(forDuration: 0.1, thenDragTo: pullEnd)

        XCTAssertTrue(refreshedCard.waitForExistence(timeout: 8))
        XCTAssertFalse(element("offline-banner").exists)
    }

    private func searchAcrossOrganisations() {
        let picker = app.buttons["repo-picker"]
        picker.tap()

        let search = app.searchFields["Search repositories"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("other-org")

        let organisationRepo = app.buttons["repo-other-org/operations"]
        XCTAssertTrue(organisationRepo.waitForExistence(timeout: 5))
        organisationRepo.tap()
        XCTAssertEqual(picker.value as? String, "other-org/operations")

        picker.tap()
        let secondSearch = app.searchFields["Search repositories"]
        XCTAssertTrue(secondSearch.waitForExistence(timeout: 5))
        secondSearch.tap()
        secondSearch.typeText("board-api")
        let boardAPI = app.buttons["repo-example-user/board-api"]
        XCTAssertTrue(boardAPI.waitForExistence(timeout: 5))
        boardAPI.tap()
        XCTAssertEqual(picker.value as? String, "example-user/board-api")
    }

    private func linkServer() {
        let serverField = app.textFields["server-url-field"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        serverField.tap()
        serverField.typeText("http://192.168.50.10:8787")

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

        let commentField = app.textFields["comment-body-field"]
        XCTAssertTrue(commentField.waitForExistence(timeout: 5))
        commentField.tap()
        commentField.typeText("Please verify the follow-up fix.")
        app.buttons["post-comment-button"].tap()
        XCTAssertTrue(app.staticTexts["Please verify the follow-up fix."].waitForExistence(timeout: 5))

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

        XCTAssertTrue(element("work-overview").waitForExistence(timeout: 8))
        XCTAssertTrue(element("overview-card-other-org/operations-7").exists)
        XCTAssertFalse(app.textFields["server-url-field"].exists)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
