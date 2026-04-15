//
//  RenameWorkspaceSheet.swift
//  gmax
//
//  Created by Gale Williams on 4/15/26.
//

import SwiftUI

struct WorkspaceRenameSheet: View {
	@Binding var title: String
	let onCancel: () -> Void
	let onSave: () -> Void

	var body: some View {
		let canSave = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
		VStack(alignment: .leading, spacing: 16) {
			Text("Rename Workspace")
				.font(.title3.weight(.semibold))

			Text("Choose the name that should appear in the sidebar, window title, and workspace actions.")
				.font(.subheadline)
				.foregroundStyle(.secondary)

			TextField("Workspace Name", text: $title)
				.textFieldStyle(.roundedBorder)
				.accessibilityIdentifier("sidebar.renameWorkspaceField")
				.onSubmit {
					guard canSave else {
						return
					}
					onSave()
				}

			HStack {
				Spacer()
				Button("Cancel", action: onCancel)
					.accessibilityIdentifier("sidebar.renameWorkspaceCancelButton")
				Button("Save", action: onSave)
					.keyboardShortcut(.defaultAction)
					.disabled(!canSave)
					.accessibilityIdentifier("sidebar.renameWorkspaceSaveButton")
			}
		}
		.padding(20)
		.frame(width: 360)
		.accessibilityIdentifier("sidebar.renameWorkspaceSheet")
	}
}
