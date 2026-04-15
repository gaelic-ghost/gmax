//
//  ContentPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct ContentPane: View {
	@ObservedObject var model: ShellModel
	@Binding var selectedWorkspaceID: WorkspaceID?

	var body: some View {
		if let workspace = selectedWorkspaceID.flatMap({ workspaceID in
			model.workspaces.first(where: { $0.id == workspaceID })
		}) {
			Group {
				if let root = workspace.root {
					ContentPaneNodeView(
						node: root,
						focusedPaneID: workspace.focusedPaneID,
						controllerForPane: { pane in
							model.paneControllers.controller(
								for: pane,
								session: model.sessions.ensureSession(id: pane.sessionID)
							)
						},
						onUpdateSplitFraction: { splitID, fraction in
							model.setSplitFraction(fraction, for: splitID, in: workspace.id)
						},
						onFocusPane: { paneID in
							Task { @MainActor in
								await Task.yield()
								model.focusPane(paneID, in: workspace.id)
							}
						},
						onSplitPane: { paneID, direction in
							model.focusPane(paneID, in: workspace.id)
							model.splitPane(paneID, in: workspace.id, direction: direction)
						},
						onClosePane: { paneID in
							model.closePane(paneID, in: workspace.id)
						}
					)
					.coordinateSpace(name: "workspace-pane-tree")
					.focusSection()
					.accessibilityElement(children: .contain)
					.accessibilityLabel("Workspace pane area")
					.onPreferenceChange(ContentPaneFramePreferenceKey.self) { paneFrames in
						model.updatePaneFrames(paneFrames, in: workspace.id)
					}
				} else {
					ContentPaneEmptyWorkspaceView(
						workspaceTitle: workspace.title,
						onStartShell: {
							selectedWorkspaceID = model.createPane(in: workspace.id)
						}
					)
				}
			}
			.navigationTitle(workspace.title)
			.focusedSceneValue(
				\.closeEmptyWorkspaceAction,
				workspace.root == nil
					? {
						selectedWorkspaceID = model.closeWorkspace(workspace.id)
					}
					: nil
			)
		} else {
			ContentUnavailableView {
				Label("No Workspace Selected", systemImage: "sidebar.left")
			} description: {
				Text("Choose a workspace from the sidebar to inspect or edit its panes.")
			}
		}
	}
}

private struct ContentPaneNodeView: View {
	let node: PaneNode
	let focusedPaneID: PaneID?
	let controllerForPane: (PaneLeaf) -> TerminalPaneController
	let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
	let onFocusPane: (PaneID) -> Void
	let onSplitPane: (PaneID, SplitDirection) -> Void
	let onClosePane: (PaneID) -> Void

	var body: some View {
		switch node {
			case .leaf(let leaf):
				let controller = controllerForPane(leaf)
				ContentPaneLeafView(
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
				ContentPaneSplitView(
					axis: split.axis,
					fraction: split.fraction,
					onFractionChange: { onUpdateSplitFraction(split.id, $0) }
				) {
					ContentPaneNodeView(
						node: split.first,
						focusedPaneID: focusedPaneID,
						controllerForPane: controllerForPane,
						onUpdateSplitFraction: onUpdateSplitFraction,
						onFocusPane: onFocusPane,
						onSplitPane: onSplitPane,
						onClosePane: onClosePane
					)
				} second: {
					ContentPaneNodeView(
						node: split.second,
						focusedPaneID: focusedPaneID,
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

struct ContentPaneFramePreferenceKey: PreferenceKey {
	static var defaultValue: [PaneID: CGRect] = [:]

	static func reduce(value: inout [PaneID: CGRect], nextValue: () -> [PaneID: CGRect]) {
		value.merge(nextValue(), uniquingKeysWith: { _, new in new })
	}
}

private struct ContentPaneEmptyWorkspaceView: View {
	let workspaceTitle: String
	let onStartShell: () -> Void

	var body: some View {
		ContentUnavailableView {
			Label("This Workspace Has No Panes", systemImage: "rectangle.dashed")
		} description: {
			Text("Start a fresh shell to rebuild \(workspaceTitle) with one live terminal pane, or use the standard Close command to close this empty workspace.")
		} actions: {
			Button("Start Shell", action: onStartShell)
				.buttonStyle(.borderedProminent)
		}
	}
}

#Preview {
	ContentPane(model: ShellModel(), selectedWorkspaceID: .constant(nil))
}
