//
//  SidebarPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct SidebarPane: View {
    @ObservedObject var model: WorkspaceStore
    @Binding var selection: WorkspaceID?

    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding
    let openLibrary: () -> Void
    let createWorkspace: () -> Void
    let duplicateWorkspace: (WorkspaceID) -> Void
    let closeWorkspaceToLibrary: (WorkspaceID) -> Void
    let closeWorkspace: (WorkspaceID) -> Void
    let requestRenameWorkspace: (WorkspaceID) -> Void
    let requestDeleteWorkspace: (WorkspaceID) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(model.workspaces) { workspace in
                let paneCount = workspace.root?.leaves().count ?? 0
                let paneCountDescription = paneCount == 1 ? "1 pane" : "\(paneCount) panes"
                let currentBellCount = model.currentBellCount(for: workspace.id)
                NavigationLink(value: workspace.id) {
                    WorkspaceSidebarRow(
                        title: workspace.title,
                        paneCountDescription: paneCountDescription,
                        currentBellCount: currentBellCount,
                    )
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    currentBellCount > 0
                        ? "\(workspace.title), \(paneCountDescription), \(currentBellCount) bell\(currentBellCount == 1 ? "" : "s") needing attention"
                        : "\(workspace.title), \(paneCountDescription)",
                )
                .accessibilityIdentifier("sidebar.workspaceRow.\(workspace.title)")
                .contextMenu {
                    workspaceActions(for: workspace)
                }
            }
        }
        .accessibilityIdentifier("sidebar.workspaceList")
        .focused(focusedTarget, equals: .sidebar)
        .navigationTitle("Workspaces")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Open Library", systemImage: "folder", action: openLibrary)
                    .labelStyle(.iconOnly)
                    .help("Open the library (\u{2318}O)")
                    .accessibilityIdentifier("sidebar.openLibraryButton")

                Button("New Workspace", systemImage: "plus.rectangle.on.rectangle", action: createWorkspace)
                    .labelStyle(.iconOnly)
                    .help("Create a new workspace (\u{2318}N)")
                    .accessibilityIdentifier("sidebar.newWorkspaceButton")
            }
        }
    }

    @ViewBuilder
    private func workspaceActions(for workspace: Workspace) -> some View {
        Button("Rename Workspace") {
            requestRenameWorkspace(workspace.id)
        }

        Button("Duplicate Workspace Layout") {
            duplicateWorkspace(workspace.id)
        }

        Divider()

        Button("Save Workspace") {
            _ = model.saveWorkspaceToLibrary(workspace.id)
        }

        Button("Close Workspace to Library") {
            closeWorkspaceToLibrary(workspace.id)
        }

        Divider()

        Button("Close Workspace") {
            closeWorkspace(workspace.id)
        }

        Button("Delete Workspace", role: .destructive) {
            requestDeleteWorkspace(workspace.id)
        }
        .disabled(model.workspaces.count <= 1)
    }
}

private struct WorkspaceSidebarRow: View {
    let title: String
    let paneCountDescription: String
    let currentBellCount: Int

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .accessibilityIdentifier("sidebar.workspaceTitle.\(title)")
                Text(paneCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("sidebar.workspacePaneCount.\(title)")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            if currentBellCount > 0 {
                Text(String(currentBellCount))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
        }
    }
}

#Preview {
    SidebarPanePreview()
}

private struct SidebarPanePreview: View {
    @FocusState private var focusedTarget: WorkspaceFocusTarget?

    var body: some View {
        SidebarPane(
            model: WorkspaceStore(),
            selection: .constant(nil),
            focusedTarget: $focusedTarget,
            openLibrary: {},
            createWorkspace: {},
            duplicateWorkspace: { _ in },
            closeWorkspaceToLibrary: { _ in },
            closeWorkspace: { _ in },
            requestRenameWorkspace: { _ in },
            requestDeleteWorkspace: { _ in },
        )
    }
}
