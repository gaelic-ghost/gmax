//
//  SavedWorkspaceLibrarySheet.swift
//  gmax
//
//  Created by Gale Williams on 4/13/26.
//

import SwiftUI

struct SavedWorkspaceLibrarySheet: View {
	@ObservedObject var model: WorkspaceStore
	@Binding var selectedWorkspaceID: WorkspaceID?
	@Environment(\.dismiss) private var dismiss
	@State private var searchText = ""
	@State private var selectedSnapshotID: SavedWorkspaceID?

	var body: some View {
		let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		let snapshots = model.listSavedWorkspaceSnapshots(matching: query.isEmpty ? nil : query)
		let normalizeSelection = {
			if !snapshots.contains(where: { $0.id == selectedSnapshotID }) {
				selectedSnapshotID = snapshots.first?.id
			}
		}
		let open: (SavedWorkspaceID) -> Void = { snapshotID in
			guard let workspaceID = model.openSavedWorkspace(snapshotID) else { return }
			selectedWorkspaceID = workspaceID
			dismiss()
		}
		let delete: (SavedWorkspaceID) -> Void = { snapshotID in
			model.deleteSavedWorkspace(snapshotID)
			selectedSnapshotID = snapshots.first { $0.id != snapshotID }?.id
		}

		VStack(spacing: 0) {
			Group {
				if snapshots.isEmpty {
					ContentUnavailableView {
						Label("No Saved Workspaces", systemImage: "externaldrive.badge.timemachine")
					} description: {
						Text(
							query.isEmpty
								? "Save a workspace to the library to reopen its pane layout and shell history later."
								: "No saved workspaces matched that search. Try a different title, pane count, or transcript text."
						)
					}
					.accessibilityIdentifier("savedWorkspaceLibrary.emptyState")
				} else {
					List(selection: $selectedSnapshotID) {
						ForEach(snapshots) { snapshot in
							let paneCountText = snapshot.paneCount == 1 ? "1 pane" : "\(snapshot.paneCount) panes"
							let timestampText = if let lastOpenedAt = snapshot.lastOpenedAt {
								"Opened \(lastOpenedAt.formatted(.relative(presentation: .named)))"
							} else {
								"Saved \(snapshot.updatedAt.formatted(.relative(presentation: .named)))"
							}
							VStack(alignment: .leading, spacing: 6) {
								HStack(alignment: .firstTextBaseline, spacing: 8) {
									Text(snapshot.title)
										.font(.headline)
										.lineLimit(1)
										.accessibilityIdentifier("savedWorkspaceLibrary.title.\(snapshot.title)")

									if snapshot.isPinned {
										Image(systemName: "pin.fill")
											.font(.caption)
											.foregroundStyle(.secondary)
									}
								}

								HStack(spacing: 10) {
									Label(paneCountText, systemImage: "rectangle.split.3x1")
									Text(timestampText)
								}
								.font(.caption)
								.foregroundStyle(.secondary)

								if let previewText = snapshot.previewText {
									Text(previewText)
										.font(.callout)
										.foregroundStyle(.secondary)
										.lineLimit(2)
								}
							}
							.padding(.vertical, 4)
							.accessibilityIdentifier("savedWorkspaceLibrary.row.\(snapshot.title)")
							.simultaneousGesture(
								TapGesture(count: 2).onEnded {
									open(snapshot.id)
								}
							)
								.tag(snapshot.id)
								.contextMenu {
									Button("Open Workspace") {
										open(snapshot.id)
									}

									Button("Delete Saved Workspace", role: .destructive) {
										delete(snapshot.id)
									}
								}
						}
					}
					.accessibilityIdentifier("savedWorkspaceLibrary.list")
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)

			Divider()

			HStack {
				Button("Cancel") {
					dismiss()
				}
				.accessibilityIdentifier("savedWorkspaceLibrary.cancelButton")

				Spacer()

				Button("Delete") {
					guard let snapshotID = selectedSnapshotID else {
						return
					}
					delete(snapshotID)
				}
				.disabled(selectedSnapshotID == nil)
				.accessibilityIdentifier("savedWorkspaceLibrary.deleteButton")

				Button("Open") {
					guard let snapshotID = selectedSnapshotID else {
						return
					}
					open(snapshotID)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(selectedSnapshotID == nil)
				.accessibilityIdentifier("savedWorkspaceLibrary.openButton")
			}
			.padding(16)
		}
		.frame(minWidth: 620, minHeight: 420)
		.searchable(text: $searchText, prompt: "Search saved workspaces")
		.onAppear {
			normalizeSelection()
		}
		.onChange(of: query) { _, _ in
			normalizeSelection()
		}
	}
}

#Preview {
	SavedWorkspaceLibrarySheet(
		model: WorkspaceStore(),
		selectedWorkspaceID: .constant(nil)
	)
}
