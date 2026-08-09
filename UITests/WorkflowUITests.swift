// SPDX-License-Identifier: MIT

import XCTest

// TEST-ID: AHT-DYNAMIC-UI-001
/// Simulator E2E for the message-anchored Dynamic Workflow surface (spec §34): `/workflow <goal>`
/// first creates an inert candidate, exposes the exact analyzed JavaScript, and requires separate
/// approval and Start actions before any child work can run.
final class WorkflowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testWorkflowCommandShowsMessageAnchoredRecord() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MOBILELLM_DYNAMIC_WORKFLOW_RESPONSES_FIXTURE"] = "1"
        app.launch()

        let newChat = app.buttons.matching(identifier: "New chat").firstMatch
        if newChat.waitForExistence(timeout: 8) { newChat.tap() }

        let field = app.textFields["composer.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), "composer never appeared")
        field.tap()
        field.typeText("/workflow deploy Kimi K3 on iPhone 16 Pro")
        let send = app.buttons["Send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        send.tap()
        let composerDeadline = Date().addingTimeInterval(3)
        while Date() < composerDeadline {
            if !((field.value as? String) ?? "").contains("/workflow") { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertTrue(
            !((field.value as? String) ?? "").contains("/workflow"),
            "the composer must clear after a /workflow send"
        )

        // The DEBUG app seeds its online service from the build-time config and routes Responses API
        // traffic through an opt-in deterministic transport. This still exercises the production
        // provider parser/runtime path without making UI acceptance depend on a live model.
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", "Workflow: deploy Kimi K3")
        ).firstMatch
        if !row.waitForExistence(timeout: 20) {
            XCTFail("the message-anchored workflow record must appear below the initiating message")
        }
        let value = readValue(row) ?? ""
        XCTAssertTrue(
            value.contains("Generating candidate") || value.contains("Waiting for approval"),
            "the workflow must begin as an inert candidate, got '\(value)'"
        )

        let candidateDeadline = Date().addingTimeInterval(180)
        var candidateState = readValue(row) ?? ""
        while Date() < candidateDeadline,
              !candidateState.contains("Waiting for approval"),
              !candidateState.contains("Failed")
        {
            Thread.sleep(forTimeInterval: 1)
            candidateState = readValue(row) ?? candidateState
        }
        XCTAssertTrue(
            candidateState.contains("Waiting for approval"),
            "candidate generation must finish without auto-execution, got '\(candidateState)'"
        )

        row.tap()
        let sourceDisclosure = app.buttons["JavaScript source"]
        XCTAssertTrue(sourceDisclosure.waitForExistence(timeout: 20), "source disclosure is missing")
        sourceDisclosure.tap()
        let source = app.descendants(matching: .any)["workflow.source"]
        let approval = app.descendants(matching: .any)["workflow.approval"]
        XCTAssertTrue(source.waitForExistence(timeout: 5), "exact JavaScript source is not inspectable")
        XCTAssertTrue(approval.exists, "candidate approval controls are missing")
        XCTAssertFalse(app.descendants(matching: .any)["workflow.start"].exists)

        let once = app.buttons["Once"]
        XCTAssertTrue(once.exists)
        once.tap()
        let start = app.descendants(matching: .any)["workflow.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 20), "approval must queue, not auto-start")
        XCTAssertEqual(app.descendants(matching: .any)["workflow.state"].label,
                       "Approved — ready to start")

        start.tap()
        let state = app.descendants(matching: .any)["workflow.state"]
        let started = NSPredicate(format: "label == 'Running' OR label == 'Completed'")
        expectation(for: started, evaluatedWith: state)
        waitForExpectations(timeout: 20)
    }

    /// Reading `.value` immediately after `waitForExistence` can race a list re-render; retry a few
    /// snapshots before giving up.
    @MainActor
    private func readValue(_ element: XCUIElement) -> String? {
        for _ in 0 ..< 10 {
            if element.exists, let value = element.value as? String {
                return value
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

}
