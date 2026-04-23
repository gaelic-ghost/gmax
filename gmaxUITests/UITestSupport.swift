//
//  UITestSupport.swift
//  gmaxUITests
//
//  Created by Codex on 4/14/26.
//

import XCTest

class GmaxUITestCase: XCTestCase {
    private enum UIProbe {
        static let initialWorkspaceTitle = "Workspace 1"
        static let sidebarWorkspaceListIdentifier = "sidebar.workspaceList"
        static let workspaceWindowIdentifierPrefix = "main-window-"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @discardableResult
    func launchApp(resetState: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["GMAX_PERSISTENCE_PROFILE"] = "ui-test"
        if resetState {
            app.launchEnvironment["GMAX_UI_TEST_RESET_STATE"] = "1"
        }
        app.launch()
        app.activate()
        assertWorkspaceWindowIsVisible(in: app)
        return app
    }

    func mainWorkspaceWindow(in app: XCUIApplication) -> XCUIElement {
        app.windows.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", UIProbe.workspaceWindowIdentifierPrefix),
        ).firstMatch
    }

    func assertWorkspaceWindowIsVisible(in app: XCUIApplication) {
        let workspaceList = workspaceSidebar(in: app)
        if workspaceList.waitForExistence(timeout: 2) {
            return
        }

        attemptToPresentWorkspaceWindow(in: app)

        guard workspaceList.waitForExistence(timeout: 5) else {
            XCTFail(
                """
                The main shell should expose the workspace sidebar after launch.
                The UI test harness intentionally avoids accessibility-tree and screenshot diagnostics here because they can trigger external permission flows and destabilize UI automation.
                """,
            )
            return
        }
    }

    func workspaceSidebar(in app: XCUIApplication) -> XCUIElement {
        mainWorkspaceWindow(in: app).descendants(matching: .any)[UIProbe.sidebarWorkspaceListIdentifier]
    }

    func attemptToPresentWorkspaceWindow(in app: XCUIApplication) {
        app.typeKey("n", modifierFlags: .command)
    }

    func createWorkspace(titled title: String, in app: XCUIApplication) {
        app.typeKey("n", modifierFlags: [.command, .shift])
        assertWorkspaceExists(title, in: app)
    }

    func assertWorkspaceExists(_ title: String, in app: XCUIApplication) {
        let workspaceRow = sidebarWorkspaceRow(titled: title, in: app)
        XCTAssertTrue(
            workspaceRow.waitForExistence(timeout: 5),
            "The workspace titled \(title) should be visible in the sidebar.",
        )
    }

    func assertWorkspaceDoesNotExist(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(
            waitForNonExistence(timeout: 2) {
                self.sidebarWorkspaceRow(titled: title, in: app)
            },
            "The workspace titled \(title) should not remain visible in the sidebar.",
        )
    }

    func selectWorkspace(_ title: String, in app: XCUIApplication) {
        let workspaceLabel = sidebarWorkspaceRow(titled: title, in: app)
        XCTAssertTrue(
            workspaceLabel.waitForExistence(timeout: 5),
            "The workspace titled \(title) must exist before it can be selected.",
        )
        workspaceLabel.click()
    }

    func chooseMenuBarAction(
        menuBarItem title: String,
        action actionTitle: String,
        in app: XCUIApplication,
    ) {
        let menuBarItem = app.menuBars.menuBarItems[title]
        XCTAssertTrue(
            menuBarItem.waitForExistence(timeout: 5),
            "The app menu bar should contain the menu titled \(title).",
        )
        menuBarItem.click()

        let menuItem = app.menuBars.menuItems[actionTitle]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 5),
            "The \(title) menu should contain the action titled \(actionTitle).",
        )
        XCTAssertTrue(
            menuItem.isEnabled,
            "The \(title) menu action titled \(actionTitle) should be enabled before the UI test attempts to invoke it.",
        )
        menuItem.click()
    }

    func openSavedWorkspaceLibrary(in app: XCUIApplication) {
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(
            savedWorkspaceLibraryOpenButton(in: app).waitForExistence(timeout: 5),
            "The saved-workspace library sheet should appear after requesting it.",
        )
    }

    func openSavedWorkspaceLibraryFromToolbar(in app: XCUIApplication) {
        let button = openSavedWorkspacesButton(in: app)
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "The main shell toolbar should expose the saved-workspace library button.",
        )
        button.click()
        XCTAssertTrue(
            savedWorkspaceLibraryCancelButton(in: app).waitForExistence(timeout: 5),
            "The saved-workspace library sheet should appear after invoking the toolbar button.",
        )
    }

    func savedWorkspaceLibraryOpenButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["savedWorkspaceLibrary.openButton"]
        if identifiedButton.exists {
            return identifiedButton
        }
        return app.buttons["Open"]
    }

    func savedWorkspaceLibraryCancelButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["savedWorkspaceLibrary.cancelButton"]
        if identifiedButton.exists {
            return identifiedButton
        }
        return app.buttons["Cancel"]
    }

    func savedWorkspaceLibraryDeleteButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["savedWorkspaceLibrary.deleteButton"]
        if identifiedButton.exists {
            return identifiedButton
        }
        return app.buttons["Delete"]
    }

    func sidebarDeleteWorkspaceCancelButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["sidebar.deleteWorkspaceCancelButton"]
    }

    func sidebarDeleteWorkspaceConfirmButton(in app: XCUIApplication) -> XCUIElement {
        app.buttons["sidebar.deleteWorkspaceConfirmButton"]
    }

    func sidebarWorkspaceRow(titled title: String, in scope: XCUIElement) -> XCUIElement {
        let workspaceList = scope.descendants(matching: .any)[UIProbe.sidebarWorkspaceListIdentifier]
        return workspaceList.descendants(matching: .any)["sidebar.workspaceRow.\(title)"].firstMatch
    }

    func sidebarWorkspacePaneCount(titled title: String, in scope: XCUIElement) -> XCUIElement {
        let workspaceList = scope.descendants(matching: .any)[UIProbe.sidebarWorkspaceListIdentifier]
        return workspaceList.staticTexts["sidebar.workspacePaneCount.\(title)"].firstMatch
    }

    func sidebarWorkspaceRowLabel(titled title: String, in scope: XCUIElement) -> String {
        sidebarWorkspaceRow(titled: title, in: scope).label
    }

    func savedWorkspaceLibraryRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
        let libraryList = app.descendants(matching: .any)["savedWorkspaceLibrary.list"]
        let identifiedTitle = libraryList.staticTexts["savedWorkspaceLibrary.title.\(title)"]
        if identifiedTitle.exists {
            return identifiedTitle
        }

        let visibleTitle = libraryList.staticTexts[title]
        if visibleTitle.exists {
            return visibleTitle
        }

        let identifiedRow = libraryList.outlines.cells.containing(.staticText, identifier: "savedWorkspaceLibrary.title.\(title)").firstMatch
        if identifiedRow.exists {
            return identifiedRow
        }

        return libraryList.staticTexts[title]
    }

    func toggleInspectorButton(in app: XCUIApplication) -> XCUIElement {
        mainWorkspaceWindow(in: app).buttons["workspaceWindow.toggleInspectorButton"]
    }

    func openSavedWorkspacesButton(in app: XCUIApplication) -> XCUIElement {
        mainWorkspaceWindow(in: app).buttons["workspaceWindow.openSavedWorkspacesButton"]
    }

    func newWorkspaceButton(in app: XCUIApplication) -> XCUIElement {
        mainWorkspaceWindow(in: app).buttons["workspaceWindow.newWorkspaceButton"]
    }

    func focusFirstVisiblePane(in app: XCUIApplication) {
        let pane = mainWorkspaceWindow(in: app).descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "contentPane.leaf."))
            .firstMatch
        XCTAssertTrue(
            pane.waitForExistence(timeout: 5),
            "The workspace content area should expose at least one pane before the test tries to focus it.",
        )
        pane.click()
    }

    @discardableResult
    func waitForNonExistence(
        timeout: TimeInterval,
        pollInterval: TimeInterval = 0.1,
        element: () -> XCUIElement,
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let currentElement = element()
            if !currentElement.exists || !currentElement.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }

        let currentElement = element()
        return !currentElement.exists || !currentElement.isHittable
    }
}
