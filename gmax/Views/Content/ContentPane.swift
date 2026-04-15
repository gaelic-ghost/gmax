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
		if let workspace = selectedWorkspaceID.flatMap(model.workspace(for:)) {
			Group {
				if workspace.root != nil {
					WorkspacePaneTreeView(
						workspace: workspace,
						controllerForPane: { pane in
							model.controller(for: pane)
						},
						onUpdateSplitFraction: { splitID, fraction in
							model.setSplitFraction(fraction, for: splitID, in: workspace.id)
						},
						onUpdatePaneFrames: { paneFrames in
							model.updatePaneFrames(paneFrames, in: workspace.id)
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
							model.focusPane(paneID, in: workspace.id)
							let outcome = model.closeFocusedPane(in: workspace.id)
							selectedWorkspaceID = outcome.nextSelectedWorkspaceID
						}
					)
				} else {
					EmptyWorkspaceView(
						workspaceTitle: workspace.title,
						onStartShell: {
							selectedWorkspaceID = model.createPane(in: workspace.id)
						}
					)
				}
			}
			.focusedSceneValue(
				\.closeWorkspaceCommand,
				workspace.root == nil
					? {
						selectedWorkspaceID = model.closeWorkspace(workspace.id).nextSelectedWorkspaceID
					}
					: nil
			)
			.navigationTitle(workspace.title)
		} else {
			ContentUnavailableView {
				Label("No Workspace Selected", systemImage: "sidebar.left")
			} description: {
				Text("Choose a workspace from the sidebar to inspect or edit its panes.")
			}
		}
	}
}

private struct EmptyWorkspaceView: View {
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
