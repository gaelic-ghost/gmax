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
    let browserOmniboxRevealIDByPaneID: [PaneID: Int]

    var body: some View {
        let workspace = selectedWorkspaceID.flatMap { workspaceID in model.workspaces.first { $0.id == workspaceID } }
        if let workspace {
            Group {
                if let root = workspace.root {
                    ContentPaneNodeView(
                        node: root,
                        focusedTarget: focusedTarget,
                        model: model,
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
                        browserOmniboxRevealIDByPaneID: browserOmniboxRevealIDByPaneID,
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
    @ObservedObject var model: WorkspaceStore

    let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
    let onMovePaneFocus: (PaneFocusDirection) -> Void
    let onSplitPane: (PaneID, SplitDirection) -> Void
    let onClosePane: (PaneID) -> Void
    let browserOmniboxRevealIDByPaneID: [PaneID: Int]

    var body: some View {
        switch node {
            case let .leaf(leaf):
                Group {
                    if let sessionID = leaf.terminalSessionID {
                        let controller = model.paneControllers.controller(
                            for: leaf,
                            session: model.sessions.ensureSession(id: sessionID),
                        )
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
                    } else if let sessionID = leaf.browserSessionID {
                        let controller = model.browserPaneControllers.controller(
                            for: leaf,
                            session: model.browserSessions.ensureSession(id: sessionID),
                        )
                        BrowserPaneLeafView(
                            pane: leaf,
                            controller: controller,
                            session: controller.session,
                            focusedTarget: focusedTarget,
                            onSplitRight: {
                                onSplitPane(leaf.id, .right)
                            },
                            onSplitDown: {
                                onSplitPane(leaf.id, .down)
                            },
                            onClose: {
                                onClosePane(leaf.id)
                            },
                            omniboxRevealID: browserOmniboxRevealIDByPaneID[leaf.id] ?? 0,
                        )
                    } else {
                        ContentPaneUnsupportedLeafView(
                            pane: leaf,
                            focusedTarget: focusedTarget,
                        )
                    }
                }

            case let .split(split):
                ContentPaneSplitView(
                    axis: split.axis,
                    fraction: split.fraction,
                    onFractionChange: { onUpdateSplitFraction(split.id, $0) },
                ) {
                    ContentPaneNodeView(
                        node: split.first,
                        focusedTarget: focusedTarget,
                        model: model,
                        onUpdateSplitFraction: onUpdateSplitFraction,
                        onMovePaneFocus: onMovePaneFocus,
                        onSplitPane: onSplitPane,
                        onClosePane: onClosePane,
                        browserOmniboxRevealIDByPaneID: browserOmniboxRevealIDByPaneID,
                    )
                } second: {
                    ContentPaneNodeView(
                        node: split.second,
                        focusedTarget: focusedTarget,
                        model: model,
                        onUpdateSplitFraction: onUpdateSplitFraction,
                        onMovePaneFocus: onMovePaneFocus,
                        onSplitPane: onSplitPane,
                        onClosePane: onClosePane,
                        browserOmniboxRevealIDByPaneID: browserOmniboxRevealIDByPaneID,
                    )
                }
        }
    }
}

private struct BrowserPaneLeafView: View {
    let pane: PaneLeaf
    let controller: BrowserPaneController
    @ObservedObject var session: BrowserSession

    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClose: () -> Void
    let omniboxRevealID: Int

    var body: some View {
        BrowserPaneChromeView(
            pane: pane,
            controller: controller,
            session: session,
            focusedTarget: focusedTarget,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClose: onClose,
            omniboxRevealID: omniboxRevealID,
        )
    }
}

private struct ContentPaneUnsupportedLeafView: View {
    let pane: PaneLeaf
    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding

    var body: some View {
        let isFocused = focusedTarget.wrappedValue == .pane(pane.id)
        let backgroundStyle = isFocused
            ? AnyShapeStyle(.tint.opacity(0.18))
            : AnyShapeStyle(Color.secondary.opacity(0.12))
        ContentUnavailableView {
            Label("Pane Content Unavailable", systemImage: "globe")
        } description: {
            Text("This pane uses a non-terminal content type that the current build cannot render yet.")
        }
        .focusable(interactions: .edit)
        .focused(focusedTarget, equals: .pane(pane.id))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundStyle)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unsupported pane")
        .accessibilityValue(isFocused ? "Focused" : "Not focused")
        .accessibilityIdentifier("contentPane.unsupportedLeaf.\(pane.id.rawValue.uuidString)")
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
            browserOmniboxRevealIDByPaneID: [:],
        )
    }
}
