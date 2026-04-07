//
//  SidebarPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct SidebarPane: View {
	@ObservedObject var model: ShellModel

	var body: some View {
		List(selection: selectedWorkspaceBinding) {
			ForEach(model.workspaces) { workspace in
				VStack(alignment: .leading, spacing: 4) {
					Text(workspace.title)
					Text("\(workspace.paneCount) panes")
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.tag(workspace.id)
			}
		}
		.navigationTitle("Workspaces")
	}

	private var selectedWorkspaceBinding: Binding<WorkspaceID?> {
		Binding(
			get: { model.selectedWorkspaceID },
			set: { newValue in
				guard let newValue else {
					return
				}
				model.selectWorkspace(newValue)
			}
		)
	}
}

#Preview {
	SidebarPane(model: ShellModel())
}
