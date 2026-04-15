//
//  gmaxApp+Actions.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import SwiftUI

extension FocusedValues {
	@Entry var selectedWorkspaceSelection: Binding<WorkspaceID?>?
	@Entry var openSavedWorkspaceLibraryAction: (() -> Void)?
	@Entry var presentWorkspaceRenameAction: ((WorkspaceID) -> Void)?
	@Entry var presentWorkspaceDeletionAction: ((WorkspaceID) -> Void)?
	@Entry var closeFocusedPaneAction: (() -> Void)?
	@Entry var closeEmptyWorkspaceAction: (() -> Void)?
}
