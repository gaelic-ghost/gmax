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
    @State private var selectedLibraryItemID: UUID?
    @State private var libraryRefreshToken = 0

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let liveWorkspaceIDs = Set(model.workspaces.map(\.id))
        let workspaceLibraryItems = {
            _ = libraryRefreshToken
            return model
                .listLibraryItems(matching: query.isEmpty ? nil : query)
                .filter { libraryItem in
                    guard libraryItem.kind == .workspace, let workspaceID = libraryItem.workspaceID else {
                        return false
                    }

                    return !liveWorkspaceIDs.contains(workspaceID)
                }
        }()
        let normalizeSelection = {
            if !workspaceLibraryItems.contains(where: { $0.id == selectedLibraryItemID }) {
                selectedLibraryItemID = workspaceLibraryItems.first?.id
            }
        }
        let open: (UUID) -> Void = { libraryItemID in
            guard let workspaceID = model.openWorkspaceLibraryItem(libraryItemID) else { return }

            selectedWorkspaceID = workspaceID
            dismiss()
        }
        let delete: (UUID) -> Void = { libraryItemID in
            model.deleteLibraryItem(libraryItemID)
            selectedLibraryItemID = workspaceLibraryItems.first { $0.id != libraryItemID }?.id
            libraryRefreshToken += 1
        }

        VStack(spacing: 0) {
            Group {
                if workspaceLibraryItems.isEmpty {
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
                    List(selection: $selectedLibraryItemID) {
                        ForEach(workspaceLibraryItems) { libraryItem in
                            let paneCountText = libraryItem.paneCount == 1 ? "1 pane" : "\(libraryItem.paneCount) panes"
                            let timestampText = if let lastOpenedAt = libraryItem.lastOpenedAt {
                                "Opened \(lastOpenedAt.formatted(.relative(presentation: .named)))"
                            } else {
                                "Saved \(libraryItem.updatedAt.formatted(.relative(presentation: .named)))"
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(libraryItem.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .accessibilityIdentifier("savedWorkspaceLibrary.title.\(libraryItem.title)")

                                    if libraryItem.isPinned {
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

                                if let previewText = libraryItem.previewText {
                                    Text(previewText)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("savedWorkspaceLibrary.row.\(libraryItem.title)")
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    open(libraryItem.id)
                                },
                            )
                            .tag(libraryItem.id)
                            .contextMenu {
                                Button("Open Workspace") {
                                    open(libraryItem.id)
                                }

                                Button("Delete Saved Workspace", role: .destructive) {
                                    delete(libraryItem.id)
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
                    guard let libraryItemID = selectedLibraryItemID ?? workspaceLibraryItems.first?.id else {
                        return
                    }

                    delete(libraryItemID)
                }
                .disabled(workspaceLibraryItems.isEmpty)
                .accessibilityIdentifier("savedWorkspaceLibrary.deleteButton")

                Button("Open") {
                    guard let libraryItemID = selectedLibraryItemID ?? workspaceLibraryItems.first?.id else {
                        return
                    }

                    open(libraryItemID)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(workspaceLibraryItems.isEmpty)
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
