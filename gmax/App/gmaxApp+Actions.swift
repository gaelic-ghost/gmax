//
//  gmaxApp+Actions.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import Observation
import SwiftUI

@MainActor
@Observable
final class MainShellSceneContext {
	let shellModel: ShellModel

	var selectedWorkspaceID: WorkspaceID?
	var workspacePendingDeletionID: WorkspaceID?
	var workspacePendingRenameID: WorkspaceID?
	var workspaceRenameTitleDraft = ""
	var isBypassingLastPaneCloseConfirmation = false
	var isSavedWorkspaceLibraryPresented = false
	var columnVisibility: NavigationSplitViewVisibility
	var isInspectorVisible: Bool

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
	}
}

extension FocusedValues {
	@Entry var mainShellSceneContext: MainShellSceneContext?
}
