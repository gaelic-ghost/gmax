//
//  SavedWorkspaceLibrarySheet.swift
//  gmax
//
//  Created by Gale Williams on 4/13/26.
//

import SwiftUI

struct SavedWorkspaceLibrarySheet: View {
	@ObservedObject var model: ShellModel
	@Binding var selectedWorkspaceID: WorkspaceID?
	@Environment(\.dismiss) private var dismiss
	@State private var searchText = ""
	@State private var selectedSnapshotID: WorkspaceSnapshotID?

	var body: some View {
		let snapshots = displayedSnapshots

		VStack(spacing: 0) {
			Group {
				if snapshots.isEmpty {
					ContentUnavailableView {
						Label("No Saved Workspaces", systemImage: "externaldrive.badge.timemachine")
					} description: {
						Text(emptyStateDescription)
					}
					.accessibilityIdentifier("savedWorkspaceLibrary.emptyState")
				} else {
					List(selection: $selectedSnapshotID) {
						ForEach(snapshots) { snapshot in
							snapshotRow(for: snapshot)
								.tag(snapshot.id)
								.contextMenu {
									Button("Open Workspace") {
										openSnapshot(snapshot.id)
									}

									Button("Delete Saved Workspace", role: .destructive) {
										deleteSnapshot(snapshot.id)
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
					guard let selectedSnapshotID else {
						return
					}
					deleteSnapshot(selectedSnapshotID)
				}
				.disabled(selectedSnapshotID == nil)
				.accessibilityIdentifier("savedWorkspaceLibrary.deleteButton")

				Button("Open") {
					guard let selectedSnapshotID else {
						return
					}
					openSnapshot(selectedSnapshotID)
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
			synchronizeSelection(with: snapshots)
		}
		.onChange(of: searchQueryKey) { _, _ in
			synchronizeSelection(with: displayedSnapshots)
		}
	}

	@ViewBuilder
	private func snapshotRow(for snapshot: SavedWorkspaceSnapshotSummary) -> some View {
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
				Label(paneCountText(for: snapshot.paneCount), systemImage: "rectangle.split.3x1")
				Text(timestampText(for: snapshot))
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
				openSnapshot(snapshot.id)
			}
		)
	}

	private var emptyStateDescription: String {
		searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? "Save a workspace to the library to reopen its pane layout and shell history later."
			: "No saved workspaces matched that search. Try a different title, pane count, or transcript text."
	}

	private func paneCountText(for paneCount: Int) -> String {
		switch paneCount {
			case 1:
				return "1 pane"
			default:
				return "\(paneCount) panes"
		}
	}

	private func timestampText(for snapshot: SavedWorkspaceSnapshotSummary) -> String {
		if let lastOpenedAt = snapshot.lastOpenedAt {
			return "Opened \(lastOpenedAt.formatted(.relative(presentation: .named)))"
		}

		return "Saved \(snapshot.updatedAt.formatted(.relative(presentation: .named)))"
	}

	private func openSnapshot(_ snapshotID: WorkspaceSnapshotID) {
		Task { @MainActor in
			await Task.yield()
			guard let workspaceID = model.openSavedWorkspace(snapshotID) else {
				return
			}

			selectedWorkspaceID = workspaceID
			dismiss()
		}
	}

	private func deleteSnapshot(_ snapshotID: WorkspaceSnapshotID) {
		Task { @MainActor in
			await Task.yield()
			model.deleteSavedWorkspace(snapshotID)
			synchronizeSelection(with: displayedSnapshots)
		}
	}

	private var searchQueryKey: String {
		searchText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private var displayedSnapshots: [SavedWorkspaceSnapshotSummary] {
		let query = searchQueryKey
		return model.listSavedWorkspaceSnapshots(matching: query.isEmpty ? nil : query)
	}

	private func synchronizeSelection(with snapshots: [SavedWorkspaceSnapshotSummary]) {
		if !snapshots.contains(where: { $0.id == selectedSnapshotID }) {
			selectedSnapshotID = snapshots.first?.id
		}
	}
}

#Preview {
	SavedWorkspaceLibrarySheet(
		model: ShellModel(),
		selectedWorkspaceID: .constant(nil)
	)
}
