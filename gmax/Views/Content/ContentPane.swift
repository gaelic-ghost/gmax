//
//  ContentPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct ContentPane: View {
	@ObservedObject var model: ShellModel

	var body: some View {
		if let workspace = model.selectedWorkspace {
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
						model.focusPane(paneID, in: workspace.id)
					}
					)
					} else {
						ContentUnavailableView {
							Label("Workspace Empty", systemImage: "rectangle.split.1x1")
						} description: {
							Text("Create a new pane with Command-T, or press Command-W again to close this workspace.")
						} actions: {
							Button("New Pane") {
								model.createPane()
							}
							.keyboardShortcut("t", modifiers: [.command])
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
	ContentPane(model: ShellModel())
}
