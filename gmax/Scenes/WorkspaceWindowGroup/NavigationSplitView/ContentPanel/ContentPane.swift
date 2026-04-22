//
//  ContentPane.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct ContentPane: View {
    @ObservedObject var model: WorkspaceStore
    @Binding var selectedWorkspaceID: WorkspaceID?

    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding
    let onCreatePane: (WorkspaceID) -> Void
    let onSplitPane: (WorkspaceID, PaneID, SplitDirection) -> Void
    let onClosePane: (WorkspaceID, PaneID) -> Void
    let onUpdatePaneFrames: ([PaneID: CGRect]) -> Void
    let onMovePaneFocus: (PaneFocusDirection) -> Void

    var body: some View {
        let workspace = selectedWorkspaceID.flatMap { workspaceID in model.workspaces.first { $0.id == workspaceID } }
        if let workspace {
            Group {
                if let root = workspace.root {
                    ContentPaneNodeView(
                        node: root,
                        focusedTarget: focusedTarget,
                        controllerForPane: { pane in
                            model.paneControllers.controller(
                                for: pane,
                                session: model.sessions.ensureSession(id: pane.sessionID),
                            )
                        },
                        onUpdateSplitFraction: { splitID, fraction in
                            model.setSplitFraction(fraction, for: splitID, in: workspace.id)
                        },
                        onMovePaneFocus: onMovePaneFocus,
                        onSplitPane: { paneID, direction in
                            onSplitPane(workspace.id, paneID, direction)
                        },
                        onClosePane: { paneID in
                            onClosePane(workspace.id, paneID)
                        },
                    )
                    .coordinateSpace(name: "workspace-pane-tree")
                    .focusSection()
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Workspace pane area")
                    .onPreferenceChange(ContentPaneFramePreferenceKey.self) { paneFrames in
                        onUpdatePaneFrames(paneFrames)
                    }
                } else {
                    ContentPaneEmptyWorkspaceView(
                        workspaceTitle: workspace.title,
                        onStartShell: {
                            onCreatePane(workspace.id)
                        },
                    )
                }
            }
            .navigationTitle(workspace.title)
        } else {
            ContentUnavailableView {
                Label("No Workspace Selected", systemImage: "sidebar.left")
            } description: {
                Text("Choose a workspace from the sidebar to inspect or edit its panes.")
            }
        }
    }
}

private struct ContentPaneNodeView: View {
    let node: PaneNode
    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding
    let controllerForPane: (PaneLeaf) -> TerminalPaneController
    let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
    let onMovePaneFocus: (PaneFocusDirection) -> Void
    let onSplitPane: (PaneID, SplitDirection) -> Void
    let onClosePane: (PaneID) -> Void

    var body: some View {
        switch node {
            case let .leaf(leaf):
                let controller = controllerForPane(leaf)
                ContentPaneLeafView(
                    pane: leaf,
                    controller: controller,
                    session: controller.session,
                    focusedTarget: focusedTarget,
                    onMovePaneFocus: onMovePaneFocus,
                    onSplitRight: {
                        onSplitPane(leaf.id, .right)
                    },
                    onSplitDown: {
                        onSplitPane(leaf.id, .down)
                    },
                    onClose: {
                        onClosePane(leaf.id)
                    },
                )

            case let .split(split):
                ContentPaneSplitView(
                    axis: split.axis,
                    fraction: split.fraction,
                    onFractionChange: { onUpdateSplitFraction(split.id, $0) },
                ) {
                    ContentPaneNodeView(
                        node: split.first,
                        focusedTarget: focusedTarget,
                        controllerForPane: controllerForPane,
                        onUpdateSplitFraction: onUpdateSplitFraction,
                        onMovePaneFocus: onMovePaneFocus,
                        onSplitPane: onSplitPane,
                        onClosePane: onClosePane,
                    )
                } second: {
                    ContentPaneNodeView(
                        node: split.second,
                        focusedTarget: focusedTarget,
                        controllerForPane: controllerForPane,
                        onUpdateSplitFraction: onUpdateSplitFraction,
                        onMovePaneFocus: onMovePaneFocus,
                        onSplitPane: onSplitPane,
                        onClosePane: onClosePane,
                    )
                }
        }
    }
}

struct ContentPaneFramePreferenceKey: PreferenceKey {
    static var defaultValue: [PaneID: CGRect] = [:]

    static func reduce(value: inout [PaneID: CGRect], nextValue: () -> [PaneID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ContentPaneEmptyWorkspaceView: View {
    let workspaceTitle: String
    let onStartShell: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("This Workspace Has No Panes", systemImage: "rectangle.dashed")
        } description: {
            Text("Start a fresh shell to rebuild \(workspaceTitle) with one live terminal pane, or use the standard Close command to close this empty workspace.")
        } actions: {
            Button("Start Shell", action: onStartShell)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview {
    ContentPanePreview()
}

private struct ContentPanePreview: View {
    @FocusState private var focusedTarget: WorkspaceFocusTarget?

    var body: some View {
        ContentPane(
            model: WorkspaceStore(),
            selectedWorkspaceID: .constant(nil),
            focusedTarget: $focusedTarget,
            onCreatePane: { _ in },
            onSplitPane: { _, _, _ in },
            onClosePane: { _, _ in },
            onUpdatePaneFrames: { _ in },
            onMovePaneFocus: { _ in },
        )
    }
}
