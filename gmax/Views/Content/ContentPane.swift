//
//  ContentPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import SwiftUI

struct ContentPane: View {
	@ObservedObject var model: ShellModel
	@Binding var selectedWorkspaceID: WorkspaceID?

	var body: some View {
		if let workspace = selectedWorkspaceID.flatMap(model.workspace(for:)) {
			WorkspaceContent(
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
				},
				onStartShell: {
					selectedWorkspaceID = model.createPane(in: workspace.id)
				},
				onCloseWorkspace: {
					selectedWorkspaceID = model.closeWorkspace(workspace.id).nextSelectedWorkspaceID
				}
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

private struct WorkspaceContent: View {
	let workspace: Workspace
	let controllerForPane: (PaneLeaf) -> TerminalPaneController
	let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
	let onUpdatePaneFrames: ([PaneID: CGRect]) -> Void
	let onFocusPane: (PaneID) -> Void
	let onSplitPane: (PaneID, SplitDirection) -> Void
	let onClosePane: (PaneID) -> Void
	let onStartShell: () -> Void
	let onCloseWorkspace: () -> Void
	@FocusState private var isFocused: Bool

	var body: some View {
		Group {
			if workspace.root != nil {
				WorkspacePaneTreeView(
					workspace: workspace,
					controllerForPane: controllerForPane,
					onUpdateSplitFraction: onUpdateSplitFraction,
					onUpdatePaneFrames: onUpdatePaneFrames,
					onFocusPane: onFocusPane,
					onSplitPane: onSplitPane,
					onClosePane: onClosePane
				)
			} else {
				ContentUnavailableView {
					Label("This Workspace Has No Panes", systemImage: "rectangle.dashed")
				} description: {
					Text("Start a fresh shell to rebuild \(workspace.title) with one live terminal pane, or use the standard Close command to close this empty workspace.")
				} actions: {
					Button("Start Shell", action: onStartShell)
						.buttonStyle(.borderedProminent)
				}
				.focusable()
				.focused($isFocused)
				.onAppear {
					isFocused = true
				}
				.onCommand(#selector(NSWindow.performClose(_:))) {
					onCloseWorkspace()
				}
			}
		}
	}
}

#Preview {
	ContentPane(model: ShellModel(), selectedWorkspaceID: .constant(nil))
}
