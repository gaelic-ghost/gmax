//
//  WorkspacePaneTreeView.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import SwiftUI

struct WorkspacePaneTreeView: View {
	let workspace: Workspace
	let controllerForPane: (PaneLeaf) -> TerminalPaneController
	let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
	let onUpdatePaneFrames: ([PaneID: CGRect]) -> Void
	let onFocusPane: (PaneID) -> Void
	let onSplitPane: (PaneID, SplitDirection) -> Void
	let onClosePane: (PaneID) -> Void

	var body: some View {
		Group {
			if let root = workspace.root {
				PaneNodeView(
					node: root,
					focusedPaneID: workspace.focusedPaneID,
					workspaceID: workspace.id,
					controllerForPane: controllerForPane,
					onUpdateSplitFraction: onUpdateSplitFraction,
					onFocusPane: onFocusPane,
					onSplitPane: onSplitPane,
					onClosePane: onClosePane
				)
			}
		}
		.coordinateSpace(name: "workspace-pane-tree")
		.focusSection()
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Workspace pane area")
		.onPreferenceChange(PaneFramePreferenceKey.self, perform: onUpdatePaneFrames)
	}
}
