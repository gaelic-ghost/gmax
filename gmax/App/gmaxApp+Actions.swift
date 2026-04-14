//
//  gmaxApp+Actions.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import AppKit
import OSLog
import SwiftUI

extension gmaxApp {
	private var diagnosticsLogger: Logger {
		Logger.gmax(.diagnostics)
	}

	var selectedWorkspace: Workspace? {
		guard let selectedWorkspaceID else {
			return nil
		}
		return shellModel.workspace(for: selectedWorkspaceID)
	}

	var canDeleteSelectedWorkspace: Bool {
		guard let selectedWorkspaceID else {
			return false
		}
		return shellModel.canDeleteWorkspace(selectedWorkspaceID)
	}

	var canCloseWorkspace: Bool {
		selectedWorkspaceID != nil && shellModel.workspaces.count > 1
	}

	var canCloseWorkspaceToLibrary: Bool {
		canCloseWorkspace
	}

	func performContextualClose() {
		if NSApp.keyWindow?.identifier == AppWindowRole.settings.identifier {
			diagnosticsLogger.notice("The contextual close command targeted the Settings window, so the app is closing that window directly.")
			NSApp.keyWindow?.performClose(nil)
			return
		}

		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
		let outcome = shellModel.performCloseCommand()
		diagnosticsLogger.notice("Ran the contextual close command from the main shell window. Result: \(String(describing: outcome.result), privacy: .public). Next selected workspace ID: \(outcome.nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)")
		selectedWorkspaceID = outcome.nextSelectedWorkspaceID
		switch outcome.result {
			case .closeWindow:
				diagnosticsLogger.notice("The contextual close command resolved to closing the active window.")
				NSApp.keyWindow?.performClose(nil)
			case .closedPane, .closedWorkspace, .noAction:
				break
		}
	}

	func performWorkspaceClose() {
		if NSApp.keyWindow?.identifier == AppWindowRole.settings.identifier {
			diagnosticsLogger.notice("The close-workspace command was invoked while the Settings window was active, so the app is closing that window instead.")
			NSApp.keyWindow?.performClose(nil)
			return
		}

		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
		let outcome = shellModel.closeSelectedWorkspace()
		diagnosticsLogger.notice("Ran the close-workspace command from the main shell window. Result: \(String(describing: outcome.result), privacy: .public). Next selected workspace ID: \(outcome.nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)")
		selectedWorkspaceID = outcome.nextSelectedWorkspaceID
		switch outcome.result {
			case .closeWindow:
				diagnosticsLogger.notice("The close-workspace command resolved to closing the active window.")
				NSApp.keyWindow?.performClose(nil)
			case .closedWorkspace, .closedPane, .noAction:
				break
		}
	}

	func performWindowClose() {
		diagnosticsLogger.notice("Requested that the active app window close immediately.")
		NSApp.keyWindow?.performClose(nil)
	}

	func saveSelectedWorkspace() {
		guard let workspaceID = selectedWorkspaceID else {
			diagnosticsLogger.error("The app received a save-workspace command, but there is no selected workspace to save.")
			return
		}
		diagnosticsLogger.notice("Requested that the selected workspace be saved to the workspace library. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
		_ = shellModel.saveWorkspaceToLibrary(workspaceID)
	}

	func presentWorkspaceRename(for workspace: Workspace) {
		diagnosticsLogger.notice("Requested that the workspace rename sheet open for the selected workspace. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
		NotificationCenter.default.post(
			name: .presentWorkspaceRenameSheet,
			object: workspace.id
		)
	}
}
