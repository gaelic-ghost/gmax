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
    @State private var selectedSavedWorkspaceID: WorkspaceID?
    @State private var libraryRefreshToken = 0

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let savedWorkspaces = {
            _ = libraryRefreshToken
            return model.listSavedWorkspaces(matching: query.isEmpty ? nil : query)
        }()
        let normalizeSelection = {
            if !savedWorkspaces.contains(where: { $0.id == selectedSavedWorkspaceID }) {
                selectedSavedWorkspaceID = savedWorkspaces.first?.id
            }
        }
        let open: (WorkspaceID) -> Void = { savedWorkspaceID in
            guard let workspaceID = model.openSavedWorkspace(savedWorkspaceID) else { return }

            selectedWorkspaceID = workspaceID
            dismiss()
        }
        let delete: (WorkspaceID) -> Void = { savedWorkspaceID in
            model.deleteSavedWorkspace(savedWorkspaceID)
            selectedSavedWorkspaceID = savedWorkspaces.first { $0.id != savedWorkspaceID }?.id
            libraryRefreshToken += 1
        }

        VStack(spacing: 0) {
            Group {
                if savedWorkspaces.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Workspaces", systemImage: "externaldrive.badge.timemachine")
                    } description: {
                        Text(
                            query.isEmpty
                                ? "Save a workspace to the library to reopen its pane layout and shell history later."
                                : "No saved workspaces matched that search. Try a different title, pane count, or transcript text.",
                        )
                    }
                    .accessibilityIdentifier("savedWorkspaceLibrary.emptyState")
                } else {
                    List(selection: $selectedSavedWorkspaceID) {
                        ForEach(savedWorkspaces) { savedWorkspace in
                            let paneCountText = savedWorkspace.paneCount == 1 ? "1 pane" : "\(savedWorkspace.paneCount) panes"
                            let timestampText = if let lastOpenedAt = savedWorkspace.lastOpenedAt {
                                "Opened \(lastOpenedAt.formatted(.relative(presentation: .named)))"
                            } else {
                                "Saved \(savedWorkspace.updatedAt.formatted(.relative(presentation: .named)))"
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(savedWorkspace.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .accessibilityIdentifier("savedWorkspaceLibrary.title.\(savedWorkspace.title)")

                                    if savedWorkspace.isPinned {
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

                                if let previewText = savedWorkspace.previewText {
                                    Text(previewText)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("savedWorkspaceLibrary.row.\(savedWorkspace.title)")
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    open(savedWorkspace.id)
                                },
                            )
                            .tag(savedWorkspace.id)
                            .contextMenu {
                                Button("Open Workspace") {
                                    open(savedWorkspace.id)
                                }

                                Button("Delete Saved Workspace", role: .destructive) {
                                    delete(savedWorkspace.id)
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
                    guard let savedWorkspaceID = selectedSavedWorkspaceID ?? savedWorkspaces.first?.id else {
                        return
                    }

                    delete(savedWorkspaceID)
                }
                .disabled(savedWorkspaces.isEmpty)
                .accessibilityIdentifier("savedWorkspaceLibrary.deleteButton")

                Button("Open") {
                    guard let savedWorkspaceID = selectedSavedWorkspaceID ?? savedWorkspaces.first?.id else {
                        return
                    }

                    open(savedWorkspaceID)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(savedWorkspaces.isEmpty)
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
        selectedWorkspaceID: .constant(nil),
    )
}
