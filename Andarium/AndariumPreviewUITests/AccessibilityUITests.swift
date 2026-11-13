// SPDX-License-Identifier: GPL-2.0-or-later
import XCTest

/// The Simulator preview driven as VoiceOver drives it: every screen passes
/// Apple's audit for element descriptions and traits, TalkBack's switch sits
/// in the session's Settings, and a first start under VoiceOver turns TalkBack
/// on by itself. `-screen` names a screen of `AppEntry`.
final class AccessibilityUITests: XCTestCase {
    private static let screens = [
        "welcome", "home", "home-new", "home-update", "home-update-failed", "home-blocked", "home-ended",
        "home-memory-warning", "home-mic-denied", "create", "resize", "system-edit", "info",
        "info-acknowledgements", "info-license", "boot", "boot-first", "boot-recovery", "session",
        "session-open", "session-stats", "session-graphics-notice", "settings", "settings-adb",
        "install-done", "install-failed", "space-pause", "space-pause-running", "recovery-open", "failed",
    ]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(_ screen: String, _ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screen", screen] + arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "\(screen) did not open")
        return app
    }

    /// Waits, within `timeout`, until `element`'s value is `value`.
    private func expect(_ element: XCUIElement, value: String, timeout: TimeInterval = 10) {
        let holds = expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: element)
        wait(for: [holds], timeout: timeout)
    }

    /// Settings' TalkBack switch, in the sheet `screen` opens on.
    @MainActor
    private func talkBackSwitch(in app: XCUIApplication) -> XCUIElement {
        let toggle = app.switches["settings-talkback"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settings has no TalkBack switch")
        return toggle
    }

    /// Flips a SwiftUI toggle: its row's own switch, not the label beside it.
    @MainActor
    private func flip(_ toggle: XCUIElement) {
        let control = toggle.switches.firstMatch
        (control.exists ? control : toggle).tap()
    }

    /// Opens the session's Settings through the side keys, as a person does.
    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let keys = app.descendants(matching: .any)["side-keys"]
        XCTAssertTrue(keys.waitForExistence(timeout: 90), "the session did not start")
        // The keys slide in with the session; a tap before they land misses.
        let landed = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: keys)
        wait(for: [landed], timeout: 10)
        keys.tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "the side keys have no Settings")
        settings.tap()
    }

    @MainActor
    func testEveryScreenHasDescriptionsAndTraits() throws {
        continueAfterFailure = true
        for screen in Self.screens {
            let app = launch(screen)
            // The audit reads what is on screen once the first frame settles.
            _ = app.descendants(matching: .any).firstMatch.waitForExistence(timeout: 10)
            try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait]) { issue in
                let element = issue.element.map { "\($0.label) (\($0.identifier))" } ?? "no element"
                XCTFail("\(screen): \(issue.compactDescription): \(element)")
                return true
            }
            app.terminate()
        }
    }

    @MainActor
    func testTheSideKeysCarryNoAccessibilityKey() {
        let app = launch("session-open")
        XCTAssertTrue(app.descendants(matching: .any)["side-keys-power"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["side-keys-accessibility"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists)
    }

    @MainActor
    func testTheSwitchTurnsTalkBackOnAndOff() {
        let app = launch("settings")
        let toggle = talkBackSwitch(in: app)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(toggle.isEnabled)
        flip(toggle)
        expect(toggle, value: "1")
        flip(toggle)
        expect(toggle, value: "0")
    }

    @MainActor
    func testTheSwitchShowsTalkBackOnWhereAndroidHasIt() {
        let app = launch("settings", "-talkBack", "on")
        expect(talkBackSwitch(in: app), value: "1")
    }

    @MainActor
    func testASystemWithoutTalkBackShowsTheSwitchUnavailable() {
        let app = launch("settings", "-talkBack", "missing")
        let toggle = talkBackSwitch(in: app)
        XCTAssertFalse(toggle.isEnabled)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(app.staticTexts["Not in this system image"].exists)
    }

    @MainActor
    func testAccessibilitySettingsLeavesTheSheetForAndroid() {
        let app = launch("settings")
        let toggle = talkBackSwitch(in: app)
        let button = app.buttons["settings-accessibility-settings"]
        XCTAssertTrue(button.exists)
        XCTAssertEqual(button.label, "Accessibility settings")
        button.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: toggle)
        wait(for: [gone], timeout: 10)
    }

    @MainActor
    func testAFirstStartUnderVoiceOverTurnsTalkBackOn() {
        let app = launch("home-new", "-voiceOver", "YES")
        let start = app.buttons["Start and set up"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        openSettings(in: app)
        expect(talkBackSwitch(in: app), value: "1")
    }

    @MainActor
    func testAFirstStartWithoutVoiceOverLeavesTalkBackOff() {
        let app = launch("home-new")
        let start = app.buttons["Start and set up"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        openSettings(in: app)
        let toggle = talkBackSwitch(in: app)
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor
    func testAcknowledgementsListTheScreenReader() {
        let app = launch("info-acknowledgements")
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        for _ in 0..<15 where !app.staticTexts["eSpeak NG"].exists {
            list.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["TalkBack"].exists)
        XCTAssertTrue(app.staticTexts["eSpeak NG"].exists)
    }
}
