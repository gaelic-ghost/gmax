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
								if outcome.result == .closeWindow {
									NSApp.keyWindow?.performClose(nil)
								}
							}
						)
				} else {
					ContentUnavailableView {
						Label("This Workspace Has No Panes", systemImage: "rectangle.dashed")
					} description: {
						Text("Start a fresh shell here to get this workspace back into a usable state.")
						} actions: {
							Button("Start Shell") {
								selectedWorkspaceID = model.createPane(in: workspace.id)
							}
							.buttonStyle(.borderedProminent)
					}
				}
			}
			.navigationTitle(workspace.title)
		} else {
			ContentUnavailableView("No Workspace Selected", systemImage: "sidebar.left")
		}
	}
}

#Preview {
	ContentPane(model: ShellModel(), selectedWorkspaceID: .constant(nil))
}
