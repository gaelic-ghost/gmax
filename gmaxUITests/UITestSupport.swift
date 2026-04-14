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
	}

	override func setUpWithError() throws {
		continueAfterFailure = false
	}

	@discardableResult
	func launchApp(resetState: Bool = true) -> XCUIApplication {
		let app = XCUIApplication()
		if resetState {
			app.launchEnvironment["GMAX_UI_TEST_RESET_STATE"] = "1"
		}
		app.launch()
		app.activate()
		assertMainShellIsVisible(in: app)
		return app
	}

	func assertMainShellIsVisible(in app: XCUIApplication) {
		let workspaceList = app.descendants(matching: .any)[UIProbe.sidebarWorkspaceListIdentifier]
		if workspaceList.waitForExistence(timeout: 2) {
			return
		}

		attemptToPresentMainShellWindow(in: app)

		guard workspaceList.waitForExistence(timeout: 5) else {
			XCTFail(
				"""
				The main shell should expose the workspace sidebar after launch.

				Current accessibility hierarchy:
				\(app.debugDescription)
				"""
			)
			return
		}
	}

	func attemptToPresentMainShellWindow(in app: XCUIApplication) {
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
			"The workspace titled \(title) should be visible in the sidebar."
		)
	}

	func assertWorkspaceDoesNotExist(_ title: String, in app: XCUIApplication) {
		let workspaceLabel = sidebarWorkspaceRow(titled: title, in: app)
		XCTAssertFalse(
			workspaceLabel.waitForExistence(timeout: 1),
			"The workspace titled \(title) should not remain visible in the sidebar."
		)
	}

	func selectWorkspace(_ title: String, in app: XCUIApplication) {
		let workspaceLabel = sidebarWorkspaceRow(titled: title, in: app)
		XCTAssertTrue(
			workspaceLabel.waitForExistence(timeout: 5),
			"The workspace titled \(title) must exist before it can be selected."
		)
		workspaceLabel.click()
	}

	func chooseMenuBarAction(
		menuBarItem title: String,
		action actionTitle: String,
		in app: XCUIApplication
	) {
		let menuBarItem = app.menuBars.menuBarItems[title]
		XCTAssertTrue(
			menuBarItem.waitForExistence(timeout: 5),
			"The app menu bar should contain the menu titled \(title)."
		)
		menuBarItem.click()

		let menuItem = app.menuBars.menuItems[actionTitle]
		XCTAssertTrue(
			menuItem.waitForExistence(timeout: 5),
			"The \(title) menu should contain the action titled \(actionTitle)."
		)
		XCTAssertTrue(
			menuItem.isEnabled,
			"The \(title) menu action titled \(actionTitle) should be enabled before the UI test attempts to invoke it."
		)
		menuItem.click()
	}

	func openSavedWorkspaceLibrary(in app: XCUIApplication) {
		app.typeKey("o", modifierFlags: .command)
		XCTAssertTrue(
			savedWorkspaceLibraryOpenButton(in: app).waitForExistence(timeout: 5),
			"The saved-workspace library sheet should appear after requesting it."
		)
	}

	func savedWorkspaceLibraryOpenButton(in app: XCUIApplication) -> XCUIElement {
		let identifiedButton = app.buttons["savedWorkspaceLibrary.openButton"]
		if identifiedButton.exists {
			return identifiedButton
		}
		return app.buttons["Open"]
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

	func sidebarWorkspaceRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
		let workspaceList = app.descendants(matching: .any)[UIProbe.sidebarWorkspaceListIdentifier]
		return workspaceList.descendants(matching: .any)["sidebar.workspaceRow.\(title)"]
	}

	func savedWorkspaceLibraryRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
		let identifiedTitle = app.staticTexts["savedWorkspaceLibrary.title.\(title)"]
		if identifiedTitle.exists {
			return identifiedTitle
		}

		let sheetScopedTitle = app.sheets.firstMatch.staticTexts[title]
		if sheetScopedTitle.exists {
			return sheetScopedTitle
		}

		return app.staticTexts[title]
	}
}
