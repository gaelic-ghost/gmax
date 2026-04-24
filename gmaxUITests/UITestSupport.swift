//
//  UITestSupport.swift
//  gmaxUITests
//
//  Created by Codex on 4/14/26.
//

import XCTest

/// Base class for the gmax macOS UI test suites.
@MainActor
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
        assertActiveWorkspaceWindowIsVisible(in: app)
        return app
    }

    func activeWorkspaceWindow(in app: XCUIApplication) -> XCUIElement {
        let windows = app.windows
            .matching(
                NSPredicate(format: "identifier BEGINSWITH %@", UIProbe.workspaceWindowIdentifierPrefix),
            )
            .allElementsBoundByIndex

        return windows.last(where: \.exists) ?? app.windows
            .matching(
                NSPredicate(format: "identifier BEGINSWITH %@", UIProbe.workspaceWindowIdentifierPrefix),
            )
            .firstMatch
    }

    func assertActiveWorkspaceWindowIsVisible(in app: XCUIApplication) {
        let workspaceList = activeWorkspaceSidebar(in: app)
        if workspaceList.waitForExistence(timeout: 2) {
            return
        }

        attemptToPresentAnotherWorkspaceWindow(in: app)

        guard workspaceList.waitForExistence(timeout: 5) else {
            XCTFail(
                """
                The active workspace window should expose the workspace sidebar after launch.
                The UI test harness intentionally avoids accessibility-tree and screenshot diagnostics here because they can trigger external permission flows and destabilize UI automation.
                """,
            )
            return
        }
    }

    func activeWorkspaceSidebar(in app: XCUIApplication) -> XCUIElement {
        activeWorkspaceWindow(in: app).descendants(matching: .any)[UIProbe.sidebarWorkspaceListIdentifier]
    }

    func attemptToPresentAnotherWorkspaceWindow(in app: XCUIApplication) {
        app.typeKey("n", modifierFlags: [.command, .shift])
    }

    func createWorkspace(titled title: String, in app: XCUIApplication) {
        app.typeKey("n", modifierFlags: .command)
        assertWorkspaceExists(title, in: app)
    }

    func assertWorkspaceExists(_ title: String, in app: XCUIApplication) {
        let workspaceRow = sidebarWorkspaceRow(titled: title, in: activeWorkspaceWindow(in: app))
        XCTAssertTrue(
            workspaceRow.waitForExistence(timeout: 5),
            "The workspace titled \(title) should be visible in the sidebar.",
        )
    }

    func assertWorkspaceDoesNotExist(_ title: String, in app: XCUIApplication) {
        XCTAssertTrue(
            waitForNonExistence(timeout: 2) {
                self.sidebarWorkspaceRow(titled: title, in: self.activeWorkspaceWindow(in: app))
            },
            "The workspace titled \(title) should not remain visible in the sidebar.",
        )
    }

    func selectWorkspace(_ title: String, in app: XCUIApplication) {
        let workspaceLabel = sidebarWorkspaceRow(titled: title, in: activeWorkspaceWindow(in: app))
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

    func menuBarAction(
        menuBarItem title: String,
        action actionTitle: String,
        in app: XCUIApplication,
    ) -> XCUIElement {
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
        return menuItem
    }

    func openLibrary(in app: XCUIApplication) {
        app.typeKey("o", modifierFlags: .command)
        XCTAssertTrue(
            libraryOpenButton(in: app).waitForExistence(timeout: 5),
            "The library sheet should appear after requesting it.",
        )
    }

    func openLibraryFromToolbar(in app: XCUIApplication) {
        let button = openLibraryButton(in: app)
        XCTAssertTrue(
            button.waitForExistence(timeout: 5),
            "The active workspace window should expose the library action in the sidebar toolbar group.",
        )
        button.click()
        XCTAssertTrue(
            libraryCancelButton(in: app).waitForExistence(timeout: 5),
            "The library sheet should appear after invoking the sidebar toolbar button.",
        )
    }

    func libraryOpenButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["library.openButton"]
        if identifiedButton.exists {
            return identifiedButton
        }
        let legacyButton = app.buttons["savedWorkspaceLibrary.openButton"]
        if legacyButton.exists {
            return legacyButton
        }
        return app.buttons["Open"]
    }

    func libraryCancelButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["library.cancelButton"]
        if identifiedButton.exists {
            return identifiedButton
        }
        let legacyButton = app.buttons["savedWorkspaceLibrary.cancelButton"]
        if legacyButton.exists {
            return legacyButton
        }
        return app.buttons["Cancel"]
    }

    func libraryDeleteButton(in app: XCUIApplication) -> XCUIElement {
        let identifiedButton = app.buttons["library.deleteButton"]
        if identifiedButton.exists {
            return identifiedButton
        }
        let legacyButton = app.buttons["savedWorkspaceLibrary.deleteButton"]
        if legacyButton.exists {
            return legacyButton
        }
        return app.buttons["Delete"]
    }

    func libraryEmptyState(in app: XCUIApplication) -> XCUIElement {
        let identifiedElement = app.descendants(matching: .any)["library.emptyState"]
        if identifiedElement.exists {
            return identifiedElement
        }
        let legacyElement = app.descendants(matching: .any)["savedWorkspaceLibrary.emptyState"]
        if legacyElement.exists {
            return legacyElement
        }

        let titledElement = app.staticTexts["No Saved Library Items"]
        if titledElement.exists {
            return titledElement
        }

        return identifiedElement
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

    func waitForSidebarWorkspaceRowLabel(
        titled title: String,
        toEqual expectedLabel: String,
        in scope: XCUIElement,
        timeout: TimeInterval = 5,
    ) -> Bool {
        let row = sidebarWorkspaceRow(titled: title, in: scope)
        let predicate = NSPredicate(format: "label == %@", expectedLabel)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: row)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    func libraryRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
        let currentList = app.descendants(matching: .any)["library.list"]
        let libraryList = if currentList.exists {
            currentList
        } else {
            app.descendants(matching: .any)["savedWorkspaceLibrary.list"]
        }
        let identifiedTitle = libraryList.staticTexts["library.title.\(title)"]
        if identifiedTitle.exists {
            return identifiedTitle
        }
        let legacyTitle = libraryList.staticTexts["savedWorkspaceLibrary.title.\(title)"]
        if legacyTitle.exists {
            return legacyTitle
        }

        let visibleTitle = libraryList.staticTexts[title]
        if visibleTitle.exists {
            return visibleTitle
        }

        let identifiedRow = libraryList.outlines.cells.containing(.staticText, identifier: "library.title.\(title)").firstMatch
        if identifiedRow.exists {
            return identifiedRow
        }
        let legacyRow = libraryList.outlines.cells.containing(.staticText, identifier: "savedWorkspaceLibrary.title.\(title)").firstMatch
        if legacyRow.exists {
            return legacyRow
        }

        return libraryList.staticTexts[title]
    }

    func toggleInspectorButton(in app: XCUIApplication) -> XCUIElement {
        activeWorkspaceWindow(in: app).buttons["workspaceWindow.toggleInspectorButton"]
    }

    func openLibraryButton(in app: XCUIApplication) -> XCUIElement {
        let activeWindow = activeWorkspaceWindow(in: app)
        let sidebarButton = activeWindow.buttons["sidebar.openLibraryButton"]
        if sidebarButton.exists {
            return sidebarButton
        }
        let currentButton = activeWindow.buttons["workspaceWindow.openLibraryButton"]
        if currentButton.exists {
            return currentButton
        }
        return activeWindow.buttons["workspaceWindow.openSavedWorkspacesButton"]
    }

    func newWorkspaceButton(in app: XCUIApplication) -> XCUIElement {
        let activeWindow = activeWorkspaceWindow(in: app)
        let sidebarButton = activeWindow.buttons["sidebar.newWorkspaceButton"]
        if sidebarButton.exists {
            return sidebarButton
        }
        return activeWindow.buttons["workspaceWindow.newWorkspaceButton"]
    }

    func focusFirstVisiblePane(in app: XCUIApplication) {
        let pane = activeWorkspaceWindow(in: app)
            .descendants(matching: .any)
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
