//
//  SavedWorkspaceLibraryUITests.swift
//  gmaxUITests
//
//  Created by Codex on 4/14/26.
//

import XCTest

final class SavedWorkspaceLibraryUITests: GmaxUITestCase {
	@MainActor
	func testPaneSplitButtonsAndContextualCloseUpdateInspectorPaneCount() throws {
		let app = launchApp()
		let workspaceRow = sidebarWorkspaceRow(titled: "Workspace 1", in: app)

		XCTAssertTrue(
			workspaceRow.waitForExistence(timeout: 5),
			"The selected workspace should be visible in the sidebar before pane lifecycle actions are tested."
		)
		XCTAssertEqual(
			workspaceRow.value as? String,
			"1 pane",
			"A fresh workspace row should report that it begins with one pane."
		)

		chooseMenuBarAction(
			menuBarItem: "Pane",
			action: "Split Right",
			in: app
		)
		XCTAssertEqual(
			workspaceRow.value as? String,
			"2 panes",
			"Splitting right should add a second pane and update the selected workspace count."
		)

		chooseMenuBarAction(
			menuBarItem: "Pane",
			action: "Split Down",
			in: app
		)
		XCTAssertEqual(
			workspaceRow.value as? String,
			"3 panes",
			"Splitting down should add a third pane and update the selected workspace count."
		)

		app.typeKey("w", modifierFlags: .command)
		XCTAssertEqual(
			workspaceRow.value as? String,
			"2 panes",
			"The contextual close command should close only the focused pane when the workspace still has multiple panes."
		)
	}

	@MainActor
	func testToolbarInspectorToggleHidesAndRestoresInspector() throws {
		let app = launchApp()

		XCTAssertEqual(
			toggleInspectorButton(in: app).label,
			"Hide Inspector",
			"The toolbar should start in the visible-inspector state for a fresh shell window."
		)

		app.typeKey("b", modifierFlags: [.command, .shift])
		XCTAssertTrue(
			toggleInspectorButton(in: app).waitForExistence(timeout: 5),
			"The inspector toggle should remain available after hiding the inspector."
		)
		XCTAssertEqual(
			toggleInspectorButton(in: app).label,
			"Show Inspector",
			"Hiding the inspector from the toolbar should flip the control into the show-inspector state."
		)

		app.typeKey("b", modifierFlags: [.command, .shift])
		XCTAssertEqual(
			toggleInspectorButton(in: app).label,
			"Hide Inspector",
			"Showing the inspector again should restore the hide-inspector state in the toolbar."
		)
	}

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
