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
	@Binding var isPresented: Bool
	@State private var searchText = ""
	@State private var selectedSnapshotID: WorkspaceSnapshotID?
	@State private var snapshots: [SavedWorkspaceSnapshotSummary] = []

	var body: some View {
		VStack(spacing: 0) {
			if snapshots.isEmpty {
				ContentUnavailableView {
					Label("No Saved Workspaces", systemImage: "externaldrive.badge.timemachine")
				} description: {
					Text(emptyStateDescription)
				}
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
			}

			Divider()

			HStack {
				Button("Cancel") {
					isPresented = false
				}

				Spacer()

				Button("Delete") {
					guard let selectedSnapshotID else {
						return
					}
					deleteSnapshot(selectedSnapshotID)
				}
				.disabled(selectedSnapshotID == nil)

				Button("Open") {
					guard let selectedSnapshotID else {
						return
					}
					openSnapshot(selectedSnapshotID)
				}
				.keyboardShortcut(.defaultAction)
				.disabled(selectedSnapshotID == nil)
			}
			.padding(16)
		}
		.frame(minWidth: 620, minHeight: 420)
		.searchable(text: $searchText, prompt: "Search saved workspaces")
		.task {
			refreshSnapshots()
		}
		.task(id: searchQueryKey) {
			refreshSnapshots()
		}
	}

	@ViewBuilder
	private func snapshotRow(for snapshot: SavedWorkspaceSnapshotSummary) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text(snapshot.title)
					.font(.headline)
					.lineLimit(1)

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
		.simultaneousGesture(
			TapGesture(count: 2).onEnded {
				openSnapshot(snapshot.id)
			}
		)
	}

	private var emptyStateDescription: String {
		searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			? "Save a workspace to the library to reopen it later with its pane layout and preserved shell history."
			: "No saved workspaces matched that search."
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

			refreshSnapshots()
			selectedWorkspaceID = workspaceID
			isPresented = false
		}
	}

	private func deleteSnapshot(_ snapshotID: WorkspaceSnapshotID) {
		Task { @MainActor in
			await Task.yield()
			model.deleteSavedWorkspace(snapshotID)
			refreshSnapshots()
		}
	}

	private var searchQueryKey: String {
		searchText.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	private func refreshSnapshots() {
		let query = searchQueryKey
		snapshots = model.listSavedWorkspaceSnapshots(matching: query.isEmpty ? nil : query)
		if !snapshots.contains(where: { $0.id == selectedSnapshotID }) {
			selectedSnapshotID = snapshots.first?.id
		}
	}
}

#Preview {
	SavedWorkspaceLibrarySheet(
		model: ShellModel(),
		selectedWorkspaceID: .constant(nil),
		isPresented: .constant(true)
	)
}
