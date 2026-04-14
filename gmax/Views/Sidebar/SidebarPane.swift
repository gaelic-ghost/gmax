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
	@State private var workspacePendingRename: Workspace?
	@State private var workspacePendingDeletion: Workspace?
	@State private var workspaceTitleDraft = ""

	var body: some View {
		List(selection: $selection) {
			ForEach(model.workspaces) { workspace in
				workspaceRow(for: workspace)
					.tag(workspace.id)
					.contextMenu {
						workspaceActions(for: workspace)
					}
			}
		}
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
				}
			}
		}
			.sheet(item: $workspacePendingRename) { workspace in
				WorkspaceRenameSheet(
					title: $workspaceTitleDraft,
				onCancel: {
					workspacePendingRename = nil
					},
					onSave: {
						model.renameWorkspace(workspace.id, to: workspaceTitleDraft)
						selection = workspace.id
						workspacePendingRename = nil
					}
			)
		}
		.alert(
			"Delete Workspace?",
			isPresented: deleteWorkspaceAlertBinding,
			presenting: workspacePendingDeletion
		) { workspace in
			Button("Delete", role: .destructive) {
				model.deleteWorkspace(workspace.id)
				workspacePendingDeletion = nil
			}
			Button("Cancel", role: .cancel) {
				workspacePendingDeletion = nil
			}
		} message: { workspace in
			Text("Delete “\(workspace.title)” and close all panes inside it? This action keeps the remaining workspaces intact.")
		}
		.onReceive(NotificationCenter.default.publisher(for: .presentWorkspaceRenameSheet)) { notification in
			guard
				let workspaceID = notification.object as? WorkspaceID,
				let workspace = model.workspace(for: workspaceID)
			else {
				return
			}

			workspaceTitleDraft = workspace.title
			workspacePendingRename = workspace
			selection = workspace.id
		}
	}

	private var selectedWorkspace: Workspace? {
		selection.flatMap(model.workspace(for:))
			?? model.workspaces.first
	}

	private var deleteWorkspaceAlertBinding: Binding<Bool> {
		Binding(
			get: { workspacePendingDeletion != nil },
			set: { isPresented in
				if !isPresented {
					workspacePendingDeletion = nil
				}
			}
		)
	}

	@ViewBuilder
	private func workspaceRow(for workspace: Workspace) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(workspace.title)
			Text(paneCountText(for: workspace))
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	@ViewBuilder
	private func workspaceActions(for workspace: Workspace) -> some View {
		Button("Rename Workspace") {
			workspaceTitleDraft = workspace.title
			workspacePendingRename = workspace
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
					selection = model.closeWorkspaceToLibrary(workspace.id).nextSelectedWorkspaceID
				}
			}
		.disabled(model.workspaces.count == 1)

		Divider()

			Button("Close Workspace") {
				Task { @MainActor in
					await Task.yield()
					selection = model.closeWorkspace(workspace.id).nextSelectedWorkspaceID
				}
			}
		.disabled(model.workspaces.count == 1)

		Button("Delete Workspace", role: .destructive) {
			workspacePendingDeletion = workspace
		}
		.disabled(!model.canDeleteWorkspace(workspace.id))
	}

	@ViewBuilder
	private func sidebarWorkspaceActions(for workspace: Workspace) -> some View {
		Button("Rename Workspace") {
			workspaceTitleDraft = workspace.title
			workspacePendingRename = workspace
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
				selection = model.closeWorkspaceToLibrary(workspace.id).nextSelectedWorkspaceID
			}
		}
		.disabled(model.workspaces.count == 1)

		Divider()

		Button("Delete Workspace", role: .destructive) {
			workspacePendingDeletion = workspace
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

private struct WorkspaceRenameSheet: View {
	@Binding var title: String
	let onCancel: () -> Void
	let onSave: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("Rename Workspace")
				.font(.title3.weight(.semibold))

			TextField("Workspace Name", text: $title)
				.textFieldStyle(.roundedBorder)
				.onSubmit {
					guard canSave else {
						return
					}
					onSave()
				}

			HStack {
				Spacer()
				Button("Cancel", action: onCancel)
				Button("Save", action: onSave)
					.keyboardShortcut(.defaultAction)
					.disabled(!canSave)
			}
		}
		.padding(20)
		.frame(width: 360)
	}

	private var canSave: Bool {
		!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
}

#Preview {
	SidebarPane(model: ShellModel(), selection: .constant(nil))
}
