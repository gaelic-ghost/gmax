//
//  SavedWorkspaceLibrarySheet.swift
//  gmax
//
//  Created by Gale Williams on 4/13/26.
//

import SwiftUI

struct LibrarySheet: View {
    @ObservedObject var model: WorkspaceStore
    @Binding var selectedWorkspaceID: WorkspaceID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var selectedLibraryItemID: UUID?
    @State private var libraryRefreshToken = 0

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryItems = {
            _ = libraryRefreshToken
            return model.listLibraryItems(matching: query.isEmpty ? nil : query)
        }()
        let normalizeSelection = {
            if !libraryItems.contains(where: { $0.id == selectedLibraryItemID }) {
                selectedLibraryItemID = libraryItems.first?.id
            }
        }
        let open: (UUID) -> Void = { libraryItemID in
            guard let openResult = model.openLibraryItem(libraryItemID) else {
                return
            }

            switch openResult {
                case let .workspace(workspaceID):
                    selectedWorkspaceID = workspaceID
                    dismiss()
                case let .window(sceneIdentity):
                    openWindow(value: sceneIdentity)
                    dismiss()
            }
        }
        let delete: (UUID) -> Void = { libraryItemID in
            model.deleteLibraryItem(libraryItemID)
            selectedLibraryItemID = libraryItems.first { $0.id != libraryItemID }?.id
            libraryRefreshToken += 1
        }

        VStack(spacing: 0) {
            Group {
                if libraryItems.isEmpty {
                    ContentUnavailableView {
                        Label("No Saved Library Items", systemImage: "externaldrive.badge.timemachine")
                    } description: {
                        Text(
                            query.isEmpty
                                ? "Saved workspaces and closed windows will appear here so they can be reopened later."
                                : "No saved workspaces or windows matched that search. Try a different title, pane count, workspace count, or transcript text.",
                        )
                    }
                    .accessibilityIdentifier("library.emptyState")
                } else {
                    List(selection: $selectedLibraryItemID) {
                        ForEach(libraryItems) { libraryItem in
                            let paneCountText = libraryItem.paneCount == 1 ? "1 pane" : "\(libraryItem.paneCount) panes"
                            let workspaceCountText = libraryItem.workspaceCount == 1 ? "1 workspace" : "\(libraryItem.workspaceCount) workspaces"
                            let timestampText = if let lastOpenedAt = libraryItem.lastOpenedAt {
                                "Opened \(lastOpenedAt.formatted(.relative(presentation: .named)))"
                            } else {
                                "\(libraryItem.kind == .window ? "Closed" : "Saved") \(libraryItem.updatedAt.formatted(.relative(presentation: .named)))"
                            }
                            let detailText = if libraryItem.kind == .workspace {
                                paneCountText
                            } else {
                                "\(workspaceCountText), \(paneCountText)"
                            }
                            let openLabel = libraryItem.kind == .window ? "Open Window" : "Open Workspace"
                            let deleteLabel = libraryItem.kind == .window ? "Delete Saved Window" : "Delete Saved Workspace"
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Image(systemName: libraryItem.kind == .window ? "macwindow" : "rectangle.split.3x1")
                                        .foregroundStyle(.secondary)

                                    Text(libraryItem.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                        .accessibilityIdentifier("library.title.\(libraryItem.title)")

                                    if libraryItem.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                HStack(spacing: 10) {
                                    Label(detailText, systemImage: "square.stack.3d.up")
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
                            .accessibilityIdentifier("library.row.\(libraryItem.title)")
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    open(libraryItem.id)
                                },
                            )
                            .tag(libraryItem.id)
                            .contextMenu {
                                Button(openLabel) {
                                    open(libraryItem.id)
                                }

                                Button(deleteLabel, role: .destructive) {
                                    delete(libraryItem.id)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("library.list")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .accessibilityIdentifier("library.cancelButton")

                Spacer()

                Button("Delete") {
                    guard let libraryItemID = selectedLibraryItemID ?? libraryItems.first?.id else {
                        return
                    }

                    delete(libraryItemID)
                }
                .disabled(libraryItems.isEmpty)
                .accessibilityIdentifier("library.deleteButton")

                Button("Open") {
                    guard let libraryItemID = selectedLibraryItemID ?? libraryItems.first?.id else {
                        return
                    }

                    open(libraryItemID)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(libraryItems.isEmpty)
                .accessibilityIdentifier("library.openButton")
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
    LibrarySheet(
        model: WorkspaceStore(),
        selectedWorkspaceID: .constant(nil),
    )
}
