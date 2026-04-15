//
//  SidebarPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct SidebarPane: View {
	@ObservedObject var model: ShellModel
	@Binding var selection: WorkspaceID?
	let requestRenameWorkspace: (WorkspaceID) -> Void
	let requestDeleteWorkspace: (WorkspaceID) -> Void

	var body: some View {
		List(selection: $selection) {
			ForEach(model.workspaces) { workspace in
				NavigationLink(value: workspace.id) {
					VStack(alignment: .leading, spacing: 4) {
						Text(workspace.title)
							.accessibilityIdentifier("sidebar.workspaceTitle.\(workspace.title)")
						Text(paneCountText(for: workspace))
							.font(.caption)
							.foregroundStyle(.secondary)
							.accessibilityIdentifier("sidebar.workspacePaneCount.\(workspace.title)")
					}
				}
					.accessibilityElement(children: .combine)
					.accessibilityLabel(workspace.title)
					.accessibilityValue(paneCountText(for: workspace))
					.accessibilityIdentifier("sidebar.workspaceRow.\(workspace.title)")
					.contextMenu {
						workspaceActions(for: workspace)
					}
			}
		}
		.accessibilityIdentifier("sidebar.workspaceList")
		.navigationTitle("Workspaces")
		.toolbar {
			ToolbarItem(placement: .automatic) {
				if let workspace = selectedWorkspace {
					Menu {
						sidebarWorkspaceActions(for: workspace)
					} label: {
						Label("Workspace Actions", systemImage: "ellipsis.circle")
					}
					.help("Show contextual workspace actions")
					.accessibilityIdentifier("sidebar.workspaceActionsButton")
				}
			}
		}
	}

	private var selectedWorkspace: Workspace? {
		selection.flatMap { workspaceID in
			model.workspaces.first(where: { $0.id == workspaceID })
		}
	}

	@ViewBuilder
	private func workspaceActions(for workspace: Workspace) -> some View {
		Button("Rename Workspace") {
			requestRenameWorkspace(workspace.id)
		}

			Button("Duplicate Workspace Layout") {
				Task { @MainActor in
					await Task.yield()
					selection = model.duplicateWorkspace(workspace.id)
				}
			}

		Divider()

			Button("Save Workspace") {
				Task { @MainActor in
					await Task.yield()
					_ = model.saveWorkspaceToLibrary(workspace.id)
				}
			}

			Button("Close Workspace to Library") {
				Task { @MainActor in
					await Task.yield()
					selection = model.closeWorkspaceToLibrary(workspace.id)
				}
			}

		Divider()

			Button("Close Workspace") {
				Task { @MainActor in
					await Task.yield()
					selection = model.closeWorkspace(workspace.id)
				}
			}

		Button("Delete Workspace", role: .destructive) {
			requestDeleteWorkspace(workspace.id)
		}
		.disabled(!model.canDeleteWorkspace(workspace.id))
	}

	@ViewBuilder
	private func sidebarWorkspaceActions(for workspace: Workspace) -> some View {
		Button("Rename Workspace") {
			requestRenameWorkspace(workspace.id)
		}

		Button("Duplicate Workspace Layout") {
			Task { @MainActor in
				await Task.yield()
				selection = model.duplicateWorkspace(workspace.id)
			}
		}

		Divider()

		Button("Close Workspace to Library") {
			Task { @MainActor in
				await Task.yield()
				selection = model.closeWorkspaceToLibrary(workspace.id)
			}
		}

		Divider()

		Button("Delete Workspace", role: .destructive) {
			requestDeleteWorkspace(workspace.id)
		}
		.disabled(!model.canDeleteWorkspace(workspace.id))
	}

	private func paneCountText(for workspace: Workspace) -> String {
		switch workspace.paneCount {
			case 1:
				return "1 pane"
			default:
				return "\(workspace.paneCount) panes"
		}
	}

}

#Preview {
	SidebarPane(
		model: ShellModel(),
		selection: .constant(nil),
		requestRenameWorkspace: { _ in },
		requestDeleteWorkspace: { _ in }
	)
}
