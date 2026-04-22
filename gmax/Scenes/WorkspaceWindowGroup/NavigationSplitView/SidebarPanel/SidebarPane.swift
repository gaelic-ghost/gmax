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
    let requestRenameWorkspace: (WorkspaceID) -> Void
    let requestDeleteWorkspace: (WorkspaceID) -> Void

    var body: some View {
        let selectedWorkspace = selection.flatMap { workspaceID in model.workspaces.first { $0.id == workspaceID } }

        List(selection: $selection) {
            ForEach(model.workspaces) { workspace in
                let paneCount = workspace.root?.leaves().count ?? 0
                let paneCountDescription = paneCount == 1 ? "1 pane" : "\(paneCount) panes"
                NavigationLink(value: workspace.id) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspace.title)
                            .accessibilityIdentifier("sidebar.workspaceTitle.\(workspace.title)")
                        Text(paneCountDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("sidebar.workspacePaneCount.\(workspace.title)")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(workspace.title), \(paneCountDescription)")
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
            ToolbarItem(placement: .automatic) {
                if let workspace = selectedWorkspace {
                    Menu {
                        workspaceActions(for: workspace)
                    } label: {
                        Label("Workspace Actions", systemImage: "ellipsis.circle")
                    }
                    .help("Show contextual workspace actions")
                    .accessibilityIdentifier("sidebar.workspaceActionsButton")
                }
            }
        }
    }

    @ViewBuilder
    private func workspaceActions(for workspace: Workspace) -> some View {
        Button("Rename Workspace") {
            requestRenameWorkspace(workspace.id)
        }

        Button("Duplicate Workspace Layout") {
            selection = model.duplicateWorkspace(workspace.id)
        }

        Divider()

        Button("Save Workspace") {
            _ = model.saveWorkspaceToLibrary(workspace.id)
        }

        Button("Close Workspace to Library") {
            selection = model.closeWorkspaceToLibrary(workspace.id)
        }

        Divider()

        Button("Close Workspace") {
            selection = model.closeWorkspace(workspace.id)
        }

        Button("Delete Workspace", role: .destructive) {
            requestDeleteWorkspace(workspace.id)
        }
        .disabled(model.workspaces.count <= 1)
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
            requestRenameWorkspace: { _ in },
            requestDeleteWorkspace: { _ in },
        )
    }
}
