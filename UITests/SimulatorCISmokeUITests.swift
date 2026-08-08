// SPDX-License-Identifier: MIT

import XCTest

// TEST-ID: AHT-LAUNCH-001
/// Deterministic, model-free simulator coverage that is safe for every pull request. It proves the
/// neutral launch contract and top-level interaction wiring without requiring downloaded weights or
/// an online-model secret; richer online and physical-model matrices remain separate release gates.
final class SimulatorCISmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testNeutralLaunchAndPrimaryNavigationAreInteractive() throws {
        let app = XCUIApplication()
        app.launch()

        let chat = app.tabBars.buttons["Chat"]
        let models = app.tabBars.buttons["Models"]
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(chat.waitForExistence(timeout: 30))
        XCTAssertTrue(models.exists)
        XCTAssertTrue(settings.exists)
        XCTAssertTrue(app.navigationBars["Chat"].exists)
        XCTAssertFalse(app.textFields["composer.field"].exists,
                       "cold launch must not reopen a conversation or load a model")

        models.tap()
        XCTAssertTrue(app.navigationBars["Models"].waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        chat.tap()
        XCTAssertTrue(app.navigationBars["Chat"].waitForExistence(timeout: 10))
    }
}
