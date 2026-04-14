//
//  PaneNodeView.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import SwiftUI

struct PaneNodeView: View {
	let node: PaneNode
	let focusedPaneID: PaneID?
	let workspaceID: WorkspaceID
	let controllerForPane: (PaneLeaf) -> TerminalPaneController
	let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
	let onFocusPane: (PaneID) -> Void
	let onSplitPane: (PaneID, SplitDirection) -> Void
	let onClosePane: (PaneID) -> Void

	var body: some View {
		switch node {
			case .leaf(let leaf):
				let controller = controllerForPane(leaf)
				PaneLeafCard(
					pane: leaf,
					controller: controller,
					session: controller.session,
					isFocused: leaf.id == focusedPaneID,
					onFocus: { onFocusPane(leaf.id) },
					onSplitRight: {
						onSplitPane(leaf.id, .right)
					},
					onSplitDown: {
						onSplitPane(leaf.id, .down)
					},
					onClose: {
						onClosePane(leaf.id)
					}
				)

			case .split(let split):
				PaneSplitContainer(
					axis: split.axis,
					fraction: split.fraction,
					onFractionChange: { onUpdateSplitFraction(split.id, $0) }
				) {
					PaneNodeView(
						node: split.first,
						focusedPaneID: focusedPaneID,
						workspaceID: workspaceID,
						controllerForPane: controllerForPane,
						onUpdateSplitFraction: onUpdateSplitFraction,
						onFocusPane: onFocusPane,
						onSplitPane: onSplitPane,
						onClosePane: onClosePane
					)
				} second: {
					PaneNodeView(
						node: split.second,
						focusedPaneID: focusedPaneID,
						workspaceID: workspaceID,
						controllerForPane: controllerForPane,
						onUpdateSplitFraction: onUpdateSplitFraction,
						onFocusPane: onFocusPane,
						onSplitPane: onSplitPane,
						onClosePane: onClosePane
					)
				}
		}
	}
}
