//
//  SavedWorkspaceLibraryUITests.swift
//  gmaxUITests
//
//  Created by Codex on 4/14/26.
//

import XCTest

final class SavedWorkspaceLibraryUITests: GmaxUITestCase {
	@MainActor
	func testCloseToLibraryThenReopenWorkspace() throws {
		let app = launchApp()

		createWorkspace(titled: "Workspace 2", in: app)
		selectWorkspace("Workspace 2", in: app)
		chooseMenuBarAction(
			menuBarItem: "Workspace",
			action: "Close Workspace to Library",
			in: app
		)

		assertWorkspaceDoesNotExist("Workspace 2", in: app)

		openSavedWorkspaceLibrary(in: app)
		let snapshotTitle = savedWorkspaceLibraryRow(titled: "Workspace 2", in: app)
		XCTAssertTrue(
			snapshotTitle.waitForExistence(timeout: 5),
			"The saved-workspace library should list the workspace that was closed into the library."
		)

		snapshotTitle.click()
		savedWorkspaceLibraryOpenButton(in: app).click()
		assertWorkspaceExists("Workspace 2", in: app)
	}

	@MainActor
	func testSavedWorkspaceLibraryCanDeleteSnapshot() throws {
		let app = launchApp()

		createWorkspace(titled: "Workspace 2", in: app)
		selectWorkspace("Workspace 2", in: app)
		chooseMenuBarAction(
			menuBarItem: "Workspace",
			action: "Close Workspace to Library",
			in: app
		)

		openSavedWorkspaceLibrary(in: app)
		let snapshotTitle = savedWorkspaceLibraryRow(titled: "Workspace 2", in: app)
		XCTAssertTrue(
			snapshotTitle.waitForExistence(timeout: 5),
			"The saved-workspace library should list the snapshot before deletion."
		)

		snapshotTitle.click()
		savedWorkspaceLibraryDeleteButton(in: app).click()

		XCTAssertTrue(
			app.staticTexts["savedWorkspaceLibrary.emptyState"].waitForExistence(timeout: 5),
			"The saved-workspace library should return to its empty state after deleting the only snapshot."
		)
		XCTAssertFalse(
			snapshotTitle.waitForExistence(timeout: 1),
			"The deleted saved-workspace snapshot should no longer appear in the library list."
		)
	}
}
