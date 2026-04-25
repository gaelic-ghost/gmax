//
//  gmaxUITestsLaunchTests.swift
//  gmaxUITests
//
//  Created by Gale Williams on 4/6/26.
//

import XCTest

final class gmaxUITestsLaunchTests: GmaxUITestCase {
    @MainActor
    func testLaunchShowsInitialWorkspaceWindow() {
        let app = launchApp()

        XCTAssertTrue(
            activeWorkspaceSidebar(in: app).exists,
            "Launching gmax should present a workspace window with the sidebar ready for interaction.",
        )
        assertWorkspaceExists("Workspace 1", in: app)
    }

    @MainActor
    func testSettingsWindowShowsWorkspaceAndTerminalPreferences() {
        let app = launchApp()

        app.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            app.descendants(matching: .any)["settings.terminal.fontPicker"].waitForExistence(timeout: 5),
            "The Settings window should expose the terminal font picker.",
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.terminal.themePicker"].exists,
            "The Settings window should expose the terminal theme picker.",
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.workspace.restoreOnLaunchToggle"].exists,
            "The Settings window should expose the workspace restoration toggle.",
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["settings.workspace.browserHomeURLField"].exists,
            "The Settings window should expose the browser home URL field.",
        )
    }
}
