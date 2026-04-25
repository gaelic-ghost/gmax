//
//  WorkspaceSidebarUITests.swift
//  gmaxUITests
//
//  Created by Codex on 4/14/26.
//

import XCTest

final class WorkspaceSidebarUITests: GmaxUITestCase {
    @MainActor
    func testRenameWorkspaceSheetSavesNewTitle() {
        let app = launchApp()

        chooseMenuBarAction(
            menuBarItem: "Workspace",
            action: "Rename Workspace",
            in: app,
        )

        let nameField = renameWorkspaceField(in: app)
        XCTAssertTrue(
            nameField.waitForExistence(timeout: 5),
            "The rename command should present a workspace name field.",
        )
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText("Project Shell")

        renameWorkspaceSaveButton(in: app).click()

        assertWorkspaceDoesNotExist("Workspace 1", in: app)
        assertWorkspaceExists("Project Shell", in: app)
    }

    @MainActor
    func testDeleteWorkspaceAlertCanCancelAndConfirm() {
        let app = launchApp()

        createWorkspace(titled: "Workspace 2", in: app)
        selectWorkspace("Workspace 2", in: app)

        chooseMenuBarAction(
            menuBarItem: "Workspace",
            action: "Delete Workspace",
            in: app,
        )

        XCTAssertTrue(
            sidebarDeleteWorkspaceCancelButton(in: app).waitForExistence(timeout: 5),
            "The delete-workspace confirmation controls should appear before a workspace is removed.",
        )

        sidebarDeleteWorkspaceCancelButton(in: app).click()
        XCTAssertTrue(
            waitForNonExistence(timeout: 2) {
                self.sidebarDeleteWorkspaceCancelButton(in: app)
            },
            "The delete-workspace confirmation controls should dismiss after cancellation.",
        )
        assertWorkspaceExists("Workspace 2", in: app)

        chooseMenuBarAction(
            menuBarItem: "Workspace",
            action: "Delete Workspace",
            in: app,
        )

        XCTAssertTrue(
            sidebarDeleteWorkspaceConfirmButton(in: app).waitForExistence(timeout: 5),
            "The delete-workspace confirmation controls should reappear for the destructive confirmation path.",
        )
        sidebarDeleteWorkspaceConfirmButton(in: app).click()

        assertWorkspaceDoesNotExist("Workspace 2", in: app)
        assertWorkspaceExists("Workspace 1", in: app)
    }
}
