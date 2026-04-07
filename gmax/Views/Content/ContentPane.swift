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
					ContentUnavailableView(
						"Workspace Empty",
						systemImage: "rectangle.split.1x1",
						description: Text("Press Command-W again to close this workspace.")
					)
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
