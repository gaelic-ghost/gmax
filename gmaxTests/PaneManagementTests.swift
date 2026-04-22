//
//  PaneManagementTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreGraphics
@testable import gmax
import Testing

@MainActor
struct PaneManagementTests {
    @Test func `split pane twice creates A nested tree and returns the newest pane`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let originalPane = try #require(workspace.root?.firstLeaf())
        let originalSession = model.sessions.ensureSession(id: originalPane.sessionID)
        originalSession.currentDirectory = "/tmp/nested-split"

        let firstInsertedPaneID = try #require(model.splitPane(originalPane.id, in: workspace.id, direction: .right))
        let newestPaneID = try #require(model.splitPane(firstInsertedPaneID, in: workspace.id, direction: .down))

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let root = try #require(updatedWorkspace.root)
        let outerSplit = try #require(extractRootSplit(from: root))
        let nestedSplit = try #require(extractRootSplit(from: outerSplit.second))
        let nestedFirstLeaf = try #require(extractRootLeaf(from: nestedSplit.first))
        let nestedSecondLeaf = try #require(extractRootLeaf(from: nestedSplit.second))
        let newestSession = try #require(model.sessions.session(for: nestedSecondLeaf.sessionID))

        #expect(updatedWorkspace.paneCount == 3)
        #expect(outerSplit.axis == .horizontal)
        #expect(extractRootLeaf(from: outerSplit.first)?.id == originalPane.id)
        #expect(nestedSplit.axis == .vertical)
        #expect(nestedFirstLeaf.id == firstInsertedPaneID)
        #expect(newestPaneID == nestedSecondLeaf.id)
        #expect(newestSession.currentDirectory == "/tmp/nested-split")
    }

    @Test func `split pane inherits the launch directory and returns the inserted pane`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: launchContextBuilder,
        )

        let originalPane = try #require(workspace.root?.firstLeaf())
        let originalSession = model.sessions.ensureSession(id: originalPane.sessionID)
        originalSession.currentDirectory = "/tmp/inherited-pane"

        let insertedPaneID = try #require(model.splitPane(originalPane.id, in: workspace.id, direction: .down))

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let root = try #require(updatedWorkspace.root)
        let split = try #require(extractRootSplit(from: root))
        let firstLeaf = try #require(extractRootLeaf(from: split.first))
        let secondLeaf = try #require(extractRootLeaf(from: split.second))
        let insertedSession = try #require(model.sessions.session(for: secondLeaf.sessionID))

        #expect(updatedWorkspace.paneCount == 2)
        #expect(split.axis == PaneSplit.Axis.vertical)
        #expect(firstLeaf.id == originalPane.id)
        #expect(insertedPaneID == secondLeaf.id)
        #expect(insertedSession.currentDirectory == "/tmp/inherited-pane")
    }

    @Test func `close pane falls back to the next surviving pane and removes the session`() throws {
        let leftPane = PaneLeaf()
        let topRightPane = PaneLeaf()
        let bottomRightPane = PaneLeaf()
        let workspace = Workspace(
            title: "Workspace 1",
            root: .split(
                PaneSplit(
                    axis: .horizontal,
                    fraction: 0.5,
                    first: .leaf(leftPane),
                    second: .split(
                        PaneSplit(
                            axis: .vertical,
                            fraction: 0.5,
                            first: .leaf(topRightPane),
                            second: .leaf(bottomRightPane),
                        ),
                    ),
                ),
            ),
        )
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        _ = model.sessions.ensureSession(id: leftPane.sessionID)
        _ = model.sessions.ensureSession(id: topRightPane.sessionID)
        _ = model.sessions.ensureSession(id: bottomRightPane.sessionID)

        let nextFocusedPaneID = model.closePane(topRightPane.id, in: workspace.id)

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        #expect(nextFocusedPaneID == bottomRightPane.id)
        #expect(updatedWorkspace.paneLeaves.map(\.id) == [leftPane.id, bottomRightPane.id])
        #expect(model.sessions.session(for: topRightPane.sessionID) == nil)
    }

    @Test func `close pane leaves an empty workspace when it was the last pane`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let pane = try #require(workspace.root?.firstLeaf())
        _ = model.sessions.ensureSession(id: pane.sessionID)
        let nextFocusedPaneID = model.closePane(pane.id, in: workspace.id)
        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))

        #expect(nextFocusedPaneID == nil)
        #expect(updatedWorkspace.root == nil)
        #expect(updatedWorkspace.paneCount == 0)
        #expect(model.sessions.session(for: pane.sessionID) == nil)
    }

    @Test func `closing the focused pane after multiple splits falls back to the adjacent surviving pane`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let originalPane = try #require(workspace.root?.firstLeaf())
        let rightPaneID = try #require(model.splitPane(originalPane.id, in: workspace.id, direction: .right))
        let bottomRightPaneID = try #require(model.splitPane(rightPaneID, in: workspace.id, direction: .down))
        let bottomRightSessionID = try #require(
            model.workspaces.first(where: { $0.id == workspace.id })?.paneLeaves.first(where: { $0.id == bottomRightPaneID })?.sessionID,
        )

        let nextFocusedPaneID = model.closePane(bottomRightPaneID, in: workspace.id)

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let survivingLeaves = updatedWorkspace.paneLeaves

        #expect(nextFocusedPaneID == rightPaneID)
        #expect(survivingLeaves.map(\.id) == [originalPane.id, rightPaneID])
        #expect(model.sessions.session(for: bottomRightSessionID) == nil)
    }

    @Test func `set split fraction updates the workspace tree`() throws {
        let leftPane = PaneLeaf()
        let rightPane = PaneLeaf()
        let split = PaneSplit(
            axis: .horizontal,
            fraction: 0.4,
            first: .leaf(leftPane),
            second: .leaf(rightPane),
        )
        let workspace = Workspace(
            title: "Workspace 1",
            root: .split(split),
        )
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.setSplitFraction(0.65, for: split.id, in: workspace.id)

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let updatedSplit = try #require(updatedWorkspace.root.flatMap(extractRootSplit(from:)))
        #expect(updatedSplit.fraction == 0.65)
    }
}

private func extractRootSplit(from node: PaneNode) -> PaneSplit? {
    guard case let .split(split) = node else {
        return nil
    }

    return split
}

private func extractRootLeaf(from node: PaneNode) -> PaneLeaf? {
    guard case let .leaf(leaf) = node else {
        return nil
    }

    return leaf
}
