//
//  SavedWorkspaceLibraryUITests.swift
//  gmaxUITests
//
//  Created by Codex on 4/14/26.
//

import XCTest

final class SavedWorkspaceLibraryUITests: GmaxUITestCase {
    @MainActor
    func testNewWorkspaceCommandCreatesWorkspace() {
        let app = launchApp()

        chooseMenuBarAction(
            menuBarItem: "File",
            action: "New Workspace",
            in: app,
        )
        assertWorkspaceExists("Workspace 2", in: app)
    }

    @MainActor
    func testPaneSplitButtonsAndContextualCloseUpdateInspectorPaneCount() {
        let app = launchApp()
        let workspaceRow = sidebarWorkspaceRow(titled: "Workspace 1", in: app)

        XCTAssertTrue(
            workspaceRow.waitForExistence(timeout: 5),
            "The selected workspace should be visible in the sidebar before pane lifecycle actions are tested.",
        )
        XCTAssertEqual(
            sidebarWorkspaceRowLabel(titled: "Workspace 1", in: app),
            "Workspace 1, 1 pane",
            "A fresh workspace row should expose its title and pane count together through the row label.",
        )
        focusFirstVisiblePane(in: app)

        chooseMenuBarAction(
            menuBarItem: "Pane",
            action: "Split Right",
            in: app,
        )
        XCTAssertTrue(
            waitForSidebarWorkspaceRowLabel(
                titled: "Workspace 1",
                toEqual: "Workspace 1, 2 panes",
                in: app,
            ),
            "Splitting right should update the selected workspace row label with the new pane count.",
        )
        focusFirstVisiblePane(in: app)

        chooseMenuBarAction(
            menuBarItem: "Pane",
            action: "Split Down",
            in: app,
        )
        XCTAssertTrue(
            waitForSidebarWorkspaceRowLabel(
                titled: "Workspace 1",
                toEqual: "Workspace 1, 3 panes",
                in: app,
            ),
            "Splitting down should update the selected workspace row label with the new pane count.",
        )
        focusFirstVisiblePane(in: app)

        let closePaneMenuItem = menuBarAction(
            menuBarItem: "File",
            action: "Close Pane",
            in: app,
        )
        XCTAssertTrue(
            closePaneMenuItem.isEnabled,
            "The File menu should resolve Command-W to Close Pane when a pane is focused in a multi-pane workspace.",
        )

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(
            waitForSidebarWorkspaceRowLabel(
                titled: "Workspace 1",
                toEqual: "Workspace 1, 2 panes",
                in: app,
            ),
            "The contextual close command should close only the focused pane when the workspace still has multiple panes.",
        )
    }

    @MainActor
    func testCommandWClosesEmptyWorkspaceBeforeWindowWhenAnotherWorkspaceExists() {
        let app = launchApp()

        createWorkspace(titled: "Workspace 2", in: app)
        selectWorkspace("Workspace 2", in: app)
        focusFirstVisiblePane(in: app)

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(
            waitForSidebarWorkspaceRowLabel(
                titled: "Workspace 2",
                toEqual: "Workspace 2, 0 panes",
                in: app,
            ),
            "The first Command-W should close the focused pane and leave the selected workspace empty.",
        )

        selectWorkspace("Workspace 2", in: app)
        app.typeKey("w", modifierFlags: .command)

        assertWorkspaceDoesNotExist("Workspace 2", in: app)
        assertWorkspaceExists("Workspace 1", in: app)
    }

    @MainActor
    func testBrowserPaneCommandCreatesPaneAndFocusesAddressBar() {
        let app = launchApp()

        focusFirstVisiblePane(in: app)
        app.typeKey("d", modifierFlags: [.command, .option])

        XCTAssertTrue(
            firstVisibleBrowserPane(in: app).waitForExistence(timeout: 5),
            "The browser split command should create a browser pane in the active workspace.",
        )

        focusFirstVisibleBrowserPane(in: app)
        app.typeKey("l", modifierFlags: .command)

        XCTAssertTrue(
            browserOmniboxField(in: app).waitForExistence(timeout: 5),
            "Command-L should reveal the focused browser pane's address field.",
        )
    }

    @MainActor
    func testToolbarInspectorToggleHidesAndRestoresInspector() {
        let app = launchApp()

        XCTAssertEqual(
            toggleInspectorButton(in: app).label,
            "Hide Inspector",
            "The toolbar should start in the visible-inspector state for a fresh shell window.",
        )

        chooseMenuBarAction(
            menuBarItem: "View",
            action: "Hide Inspector",
            in: app,
        )
        XCTAssertTrue(
            toggleInspectorButton(in: app).waitForExistence(timeout: 5),
            "The inspector toggle should remain available after hiding the inspector.",
        )
        XCTAssertEqual(
            toggleInspectorButton(in: app).label,
            "Show Inspector",
            "Hiding the inspector from the toolbar should flip the control into the show-inspector state.",
        )

        chooseMenuBarAction(
            menuBarItem: "View",
            action: "Show Inspector",
            in: app,
        )
        XCTAssertEqual(
            toggleInspectorButton(in: app).label,
            "Hide Inspector",
            "Showing the inspector again should restore the hide-inspector state in the toolbar.",
        )
    }

    @MainActor
    func testCloseToLibraryThenReopenWorkspace() {
        let app = launchApp()

        createWorkspace(titled: "Workspace 2", in: app)
        selectWorkspace("Workspace 2", in: app)
        chooseMenuBarAction(
            menuBarItem: "Workspace",
            action: "Close Workspace to Library",
            in: app,
        )

        assertWorkspaceDoesNotExist("Workspace 2", in: app)

        openLibrary(in: app)
        let savedWorkspaceTitle = libraryRow(titled: "Workspace 2", in: app)
        XCTAssertTrue(
            savedWorkspaceTitle.waitForExistence(timeout: 5),
            "The library should list the workspace that was closed into it.",
        )

        savedWorkspaceTitle.click()
        libraryOpenButton(in: app).click()
        assertWorkspaceExists("Workspace 2", in: app)
    }

    @MainActor
    func testLibraryCanDeleteSavedWorkspace() {
        let app = launchApp()

        createWorkspace(titled: "Workspace 2", in: app)
        selectWorkspace("Workspace 2", in: app)
        chooseMenuBarAction(
            menuBarItem: "Workspace",
            action: "Close Workspace to Library",
            in: app,
        )

        openLibrary(in: app)
        let savedWorkspaceTitle = libraryRow(titled: "Workspace 2", in: app)
        XCTAssertTrue(
            savedWorkspaceTitle.waitForExistence(timeout: 5),
            "The library should list the saved workspace before deletion.",
        )

        savedWorkspaceTitle.click()
        libraryDeleteButton(in: app).click()

        XCTAssertTrue(
            waitForNonExistence(timeout: 2) {
                self.libraryRow(titled: "Workspace 2", in: app)
            },
            "The deleted saved workspace should no longer appear in the library list.",
        )
        XCTAssertFalse(
            libraryDeleteButton(in: app).isEnabled,
            "The delete action should disable itself once there is no saved workspace selection left in the library.",
        )
    }

    @MainActor
    func testToolbarOpenLibraryButtonPresentsAndDismissesLibrary() {
        let app = launchApp()

        openLibraryFromToolbar(in: app)
        XCTAssertTrue(
            libraryCancelButton(in: app).waitForExistence(timeout: 5),
            "The library sheet should show its cancel control after the toolbar opens it.",
        )

        libraryCancelButton(in: app).click()
        XCTAssertTrue(
            waitForNonExistence(timeout: 2) {
                self.libraryCancelButton(in: app)
            },
            "The library sheet should dismiss after the cancel action.",
        )
    }

    @MainActor
    func testCommandWDismissesLibraryBeforeClosingWorkspace() {
        let app = launchApp()

        createWorkspace(titled: "Workspace 2", in: app)
        selectWorkspace("Workspace 2", in: app)
        openLibrary(in: app)

        app.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(
            waitForNonExistence(timeout: 2) {
                self.libraryCancelButton(in: app)
            },
            "Command-W should dismiss the frontmost library sheet before it mutates the selected workspace underneath it.",
        )
        assertWorkspaceExists("Workspace 2", in: app)
    }
}
