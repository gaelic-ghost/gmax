//
//  gmaxApp+Actions.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import AppKit
import Observation
import OSLog
import SwiftUI

struct MainShellSceneCommandState: Equatable {
	var hasSelectedWorkspace = false
	var canSplitFocusedPane = false
	var canUndoCloseWorkspace = false
	var canDeleteSelectedWorkspace = false
	var canCloseWorkspace = false
	var canCloseWorkspaceToLibrary = false
	var workspaceCount = 0
	var isInspectorVisible = true
}

@MainActor
@Observable
final class MainShellSceneContext {
	let shellModel: ShellModel

	var selectedWorkspaceID: WorkspaceID?
	var workspacePendingDeletionID: WorkspaceID?
	var isBypassingLastPaneCloseConfirmation = false
	var isSavedWorkspaceLibraryPresented = false
	var columnVisibility: NavigationSplitViewVisibility
	var isInspectorVisible: Bool

	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	init(
		shellModel: ShellModel,
		selectedWorkspaceID: WorkspaceID?,
		isSidebarVisible: Bool = true,
		isInspectorVisible: Bool = true
	) {
		self.shellModel = shellModel
		self.selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(selectedWorkspaceID)
		self.columnVisibility = isSidebarVisible ? .all : .doubleColumn
		self.isInspectorVisible = isInspectorVisible
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
	}

	var selectedWorkspace: Workspace? {
		guard let selectedWorkspaceID else {
			return nil
		}
		return shellModel.workspace(for: selectedWorkspaceID)
	}

	var workspacePendingDeletion: Workspace? {
		guard let workspacePendingDeletionID else {
			return nil
		}
		return shellModel.workspace(for: workspacePendingDeletionID)
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

	var canSplitFocusedPane: Bool {
		guard let selectedWorkspaceID else {
			return false
		}
		return shellModel.focusedPane(in: selectedWorkspaceID) != nil
	}

	var isSidebarVisible: Bool {
		columnVisibility == .all
	}

	var commandState: MainShellSceneCommandState {
		MainShellSceneCommandState(
			hasSelectedWorkspace: selectedWorkspaceID != nil,
			canSplitFocusedPane: canSplitFocusedPane,
			canUndoCloseWorkspace: shellModel.canUndoCloseWorkspace(),
			canDeleteSelectedWorkspace: canDeleteSelectedWorkspace,
			canCloseWorkspace: canCloseWorkspace,
			canCloseWorkspaceToLibrary: canCloseWorkspaceToLibrary,
			workspaceCount: shellModel.workspaces.count,
			isInspectorVisible: isInspectorVisible
		)
	}

	func applyRestoredSceneState(
		restoredSelectedWorkspaceID: WorkspaceID?,
		isSidebarVisible: Bool,
		isInspectorVisible: Bool
	) {
		self.selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(
			restoredSelectedWorkspaceID ?? selectedWorkspaceID
		)
		self.columnVisibility = isSidebarVisible ? .all : .doubleColumn
		self.isInspectorVisible = isInspectorVisible
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
		diagnosticsLogger.notice(
			"""
			Applied per-window shell scene restoration. Restored workspace selection: \(restoredSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public). \
			Normalized workspace selection: \(self.selectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public). \
			Sidebar visibility: \(isSidebarVisible ? "visible" : "hidden", privacy: .public). \
			Inspector visibility: \(isInspectorVisible ? "visible" : "hidden", privacy: .public).
			"""
		)
	}

	func normalizeSelectionAfterWorkspaceMutation() {
		selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(selectedWorkspaceID)
		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
	}

	func requestDeleteWorkspaceConfirmation(_ workspaceID: WorkspaceID) {
		guard shellModel.canDeleteWorkspace(workspaceID) else {
			diagnosticsLogger.notice(
				"Skipped presenting workspace deletion confirmation because the selected workspace cannot be deleted safely. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
			return
		}

		workspacePendingDeletionID = workspaceID
		diagnosticsLogger.notice(
			"Presented workspace deletion confirmation for the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
		)
	}

	func requestDeleteSelectedWorkspaceConfirmation() {
		guard let selectedWorkspaceID else {
			diagnosticsLogger.notice(
				"Skipped presenting workspace deletion confirmation because the active shell window has no selected workspace."
			)
			return
		}

		requestDeleteWorkspaceConfirmation(selectedWorkspaceID)
	}

	func cancelWorkspaceDeletion() {
		guard let workspacePendingDeletionID else {
			return
		}

		diagnosticsLogger.notice(
			"Dismissed workspace deletion confirmation without deleting the workspace. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)"
		)
		self.workspacePendingDeletionID = nil
	}

	func confirmWorkspaceDeletion() {
		guard let workspacePendingDeletionID else {
			diagnosticsLogger.error(
				"The app attempted to confirm workspace deletion in the active shell window, but no workspace was pending destructive confirmation."
			)
			return
		}

		shellModel.deleteWorkspace(workspacePendingDeletionID)
		diagnosticsLogger.notice(
			"Deleted a workspace after the active shell window confirmed the destructive action. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)"
		)
		self.workspacePendingDeletionID = nil
		normalizeSelectionAfterWorkspaceMutation()
	}

	func createWorkspace() {
		selectedWorkspaceID = shellModel.createWorkspace()
		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
	}

	func openSavedWorkspaceLibrary() {
		isSavedWorkspaceLibraryPresented = true
	}

	func toggleSidebar() {
		columnVisibility = columnVisibility == .all ? .doubleColumn : .all
		let resolvedColumnVisibility = String(describing: columnVisibility)
		diagnosticsLogger.notice(
			"Toggled sidebar visibility in the active shell window. New split-view column visibility: \(resolvedColumnVisibility, privacy: .public)"
		)
	}

	func toggleInspector() {
		isInspectorVisible.toggle()
		let inspectorVisibilityDescription = isInspectorVisible ? "visible" : "hidden"
		diagnosticsLogger.notice(
			"Toggled inspector visibility in the active shell window. Inspector is now \(inspectorVisibilityDescription, privacy: .public)."
		)
	}

	func undoCloseWorkspace() {
		selectedWorkspaceID = shellModel.undoCloseWorkspace()
		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
	}

	func duplicateSelectedWorkspaceLayout() {
		guard let selectedWorkspaceID else {
			return
		}

		self.selectedWorkspaceID = shellModel.duplicateWorkspace(selectedWorkspaceID)
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
	}

	func closeSelectedWorkspaceToLibrary() {
		guard let selectedWorkspaceID else {
			return
		}

		self.selectedWorkspaceID = shellModel.closeWorkspaceToLibrary(selectedWorkspaceID).nextSelectedWorkspaceID
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
	}

	func deleteSelectedWorkspace() {
		requestDeleteSelectedWorkspaceConfirmation()
	}

	func selectNextWorkspace() {
		guard !shellModel.workspaces.isEmpty else {
			selectedWorkspaceID = nil
			shellModel.setCurrentWorkspaceID(nil)
			return
		}

		guard let selectedWorkspaceID,
			  let currentIndex = shellModel.workspaces.firstIndex(where: { $0.id == selectedWorkspaceID })
		else {
			self.selectedWorkspaceID = shellModel.workspaces.first?.id
			shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
			return
		}

		let nextIndex = (currentIndex + 1) % shellModel.workspaces.count
		self.selectedWorkspaceID = shellModel.workspaces[nextIndex].id
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
	}

	func selectPreviousWorkspace() {
		guard !shellModel.workspaces.isEmpty else {
			selectedWorkspaceID = nil
			shellModel.setCurrentWorkspaceID(nil)
			return
		}

		guard let selectedWorkspaceID,
			  let currentIndex = shellModel.workspaces.firstIndex(where: { $0.id == selectedWorkspaceID })
		else {
			self.selectedWorkspaceID = shellModel.workspaces.last?.id
			shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
			return
		}

		let previousIndex = (currentIndex - 1 + shellModel.workspaces.count) % shellModel.workspaces.count
		self.selectedWorkspaceID = shellModel.workspaces[previousIndex].id
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
	}

	func movePaneFocus(_ direction: PaneFocusDirection) {
		shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
		shellModel.movePaneFocus(direction)
	}

	func splitFocusedPane(_ direction: SplitDirection) {
		guard let selectedWorkspaceID else {
			return
		}

		shellModel.splitFocusedPane(in: selectedWorkspaceID, direction)
	}

	func saveSelectedWorkspace() {
		guard let selectedWorkspaceID else {
			diagnosticsLogger.error(
				"The app received a save-workspace command for the active shell window, but that window has no selected workspace to save."
			)
			return
		}

		diagnosticsLogger.notice(
			"Requested that the selected workspace be saved to the workspace library from the active shell window. Workspace ID: \(selectedWorkspaceID.rawValue.uuidString, privacy: .public)"
		)
		_ = shellModel.saveWorkspaceToLibrary(selectedWorkspaceID)
	}

	func performContextualClose() {
		if NSApp.keyWindow?.identifier == AppWindowRole.settings.identifier {
			diagnosticsLogger.notice(
				"The contextual close command targeted the Settings window, so the app is closing that window directly."
			)
			NSApp.keyWindow?.performClose(nil)
			return
		}

		guard let selectedWorkspaceID else {
			diagnosticsLogger.notice(
				"The contextual close command was invoked without a selected workspace in the active shell window, so the app is closing the frontmost window directly."
			)
			NSApp.keyWindow?.performClose(nil)
			return
		}

		let outcome = shellModel.closeFocusedPane(in: selectedWorkspaceID)
		diagnosticsLogger.notice(
			"Ran the contextual close command from the active shell window. Result: \(String(describing: outcome.result), privacy: .public). Next selected workspace ID: \(outcome.nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)"
		)
		self.selectedWorkspaceID = outcome.nextSelectedWorkspaceID
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
		if outcome.result == .closeWindow {
			diagnosticsLogger.notice("The contextual close command resolved to closing the active window.")
			NSApp.keyWindow?.performClose(nil)
		}
	}

	func performWorkspaceClose() {
		if NSApp.keyWindow?.identifier == AppWindowRole.settings.identifier {
			diagnosticsLogger.notice(
				"The close-workspace command was invoked while the Settings window was active, so the app is closing that window instead."
			)
			NSApp.keyWindow?.performClose(nil)
			return
		}

		guard let selectedWorkspaceID else {
			diagnosticsLogger.notice(
				"The close-workspace command was invoked without a selected workspace in the active shell window, so the app is closing the frontmost window directly."
			)
			NSApp.keyWindow?.performClose(nil)
			return
		}

		let outcome = shellModel.closeWorkspace(selectedWorkspaceID)
		diagnosticsLogger.notice(
			"Ran the close-workspace command from the active shell window. Result: \(String(describing: outcome.result), privacy: .public). Next selected workspace ID: \(outcome.nextSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public)"
		)
		self.selectedWorkspaceID = outcome.nextSelectedWorkspaceID
		shellModel.setCurrentWorkspaceID(self.selectedWorkspaceID)
		if outcome.result == .closeWindow {
			diagnosticsLogger.notice("The close-workspace command resolved to closing the active window.")
			NSApp.keyWindow?.performClose(nil)
		}
	}

	func performWindowClose() {
		diagnosticsLogger.notice("Requested that the active app window close immediately.")
		NSApp.keyWindow?.performClose(nil)
	}

	func presentWorkspaceRename() {
		guard let selectedWorkspace else {
			return
		}

		diagnosticsLogger.notice(
			"Requested that the workspace rename sheet open for the selected workspace in the active shell window. Workspace title: \(selectedWorkspace.title, privacy: .public). Workspace ID: \(selectedWorkspace.id.rawValue.uuidString, privacy: .public)"
		)
		NotificationCenter.default.post(
			name: .presentWorkspaceRenameSheet,
			object: selectedWorkspace.id
		)
	}
}

extension FocusedValues {
	@Entry var mainShellSceneContext: MainShellSceneContext?
	@Entry var mainShellSceneCommandState: MainShellSceneCommandState?
}
