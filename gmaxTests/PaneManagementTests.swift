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
    @Test func `create pane fills an empty workspace and ignores missing workspaces`() throws {
        let workspace = Workspace(title: "Workspace 1", root: nil)
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let insertedPaneID = try #require(model.createPane(in: workspace.id))
        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let insertedPane = try #require(updatedWorkspace.root?.firstLeaf())
        let insertedSession = try #require(model.sessions.session(for: insertedPane.requiredTerminalSessionID))

        #expect(insertedPane.id == insertedPaneID)
        #expect(insertedSession.currentDirectory == "/tmp/gmax-tests")
        #expect(model.createPane(in: WorkspaceID()) == nil)
    }

    @Test func `create pane splits the first leaf when a workspace already has content`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let insertedPaneID = try #require(model.createPane(in: workspace.id))
        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let rootSplit = try #require(updatedWorkspace.root.flatMap(extractRootSplit(from:)))
        let secondLeaf = try #require(extractRootLeaf(from: rootSplit.second))

        #expect(rootSplit.axis == .horizontal)
        #expect(updatedWorkspace.paneCount == 2)
        #expect(secondLeaf.id == insertedPaneID)
    }

    @Test func `split pane twice creates A nested tree and returns the newest pane`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let originalPane = try #require(workspace.root?.firstLeaf())
        let originalSession = model.sessions.ensureSession(id: originalPane.requiredTerminalSessionID)
        originalSession.currentDirectory = "/tmp/nested-split"

        let firstInsertedPaneID = try #require(model.splitPane(originalPane.id, in: workspace.id, direction: .right))
        let newestPaneID = try #require(model.splitPane(firstInsertedPaneID, in: workspace.id, direction: .down))

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let root = try #require(updatedWorkspace.root)
        let outerSplit = try #require(extractRootSplit(from: root))
        let nestedSplit = try #require(extractRootSplit(from: outerSplit.second))
        let nestedFirstLeaf = try #require(extractRootLeaf(from: nestedSplit.first))
        let nestedSecondLeaf = try #require(extractRootLeaf(from: nestedSplit.second))
        let newestSession = try #require(model.sessions.session(for: nestedSecondLeaf.requiredTerminalSessionID))

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
        let originalSession = model.sessions.ensureSession(id: originalPane.requiredTerminalSessionID)
        originalSession.currentDirectory = "/tmp/inherited-pane"

        let insertedPaneID = try #require(model.splitPane(originalPane.id, in: workspace.id, direction: .down))

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let root = try #require(updatedWorkspace.root)
        let split = try #require(extractRootSplit(from: root))
        let firstLeaf = try #require(extractRootLeaf(from: split.first))
        let secondLeaf = try #require(extractRootLeaf(from: split.second))
        let insertedSession = try #require(model.sessions.session(for: secondLeaf.requiredTerminalSessionID))

        #expect(updatedWorkspace.paneCount == 2)
        #expect(split.axis == PaneSplit.Axis.vertical)
        #expect(firstLeaf.id == originalPane.id)
        #expect(insertedPaneID == secondLeaf.id)
        #expect(insertedSession.currentDirectory == "/tmp/inherited-pane")
    }

    @Test func `split pane ignores missing workspace root source and nonterminal source panes`() {
        let emptyWorkspace = Workspace(title: "Empty", root: nil)
        let browserPane = PaneLeaf(content: .browser(BrowserSessionID()))
        let browserWorkspace = Workspace(title: "Browser", root: .leaf(browserPane))
        let model = WorkspaceStore(
            workspaces: [emptyWorkspace, browserWorkspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        #expect(model.splitPane(PaneID(), in: WorkspaceID(), direction: .right) == nil)
        #expect(model.splitPane(PaneID(), in: emptyWorkspace.id, direction: .right) == nil)
        #expect(model.splitPane(PaneID(), in: browserWorkspace.id, direction: .right) == nil)
        #expect(model.splitPane(browserPane.id, in: browserWorkspace.id, direction: .right) == nil)
        #expect(model.workspaces.first(where: { $0.id == emptyWorkspace.id })?.root == nil)
        #expect(model.workspaces.first(where: { $0.id == browserWorkspace.id })?.paneCount == 1)
    }

    @Test func `close pane removes the session and collapses to surviving leaves`() throws {
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

        _ = model.sessions.ensureSession(id: leftPane.requiredTerminalSessionID)
        _ = model.sessions.ensureSession(id: topRightPane.requiredTerminalSessionID)
        _ = model.sessions.ensureSession(id: bottomRightPane.requiredTerminalSessionID)

        model.closePane(topRightPane.id, in: workspace.id)

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        #expect(updatedWorkspace.paneLeaves.map(\.id) == [leftPane.id, bottomRightPane.id])
        #expect(model.sessions.session(for: topRightPane.requiredTerminalSessionID) == nil)
    }

    @Test func `close pane leaves an empty workspace when it was the last pane`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let pane = try #require(workspace.root?.firstLeaf())
        _ = model.sessions.ensureSession(id: pane.requiredTerminalSessionID)
        model.closePane(pane.id, in: workspace.id)
        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))

        #expect(updatedWorkspace.root == nil)
        #expect(updatedWorkspace.paneCount == 0)
        #expect(model.sessions.session(for: pane.requiredTerminalSessionID) == nil)
    }

    @Test func `closing the focused pane after multiple splits preserves the surviving layout`() throws {
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
            model.workspaces.first(where: { $0.id == workspace.id })?.paneLeaves.first(where: { $0.id == bottomRightPaneID })?.requiredTerminalSessionID,
        )

        model.closePane(bottomRightPaneID, in: workspace.id)

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let survivingLeaves = updatedWorkspace.paneLeaves

        #expect(survivingLeaves.map(\.id) == [originalPane.id, rightPaneID])
        #expect(model.sessions.session(for: bottomRightSessionID) == nil)
    }

    @Test func `close pane ignores missing workspaces roots and panes`() {
        let emptyWorkspace = Workspace(title: "Empty", root: nil)
        let pane = PaneLeaf()
        let workspace = Workspace(title: "Workspace 1", root: .leaf(pane))
        let model = WorkspaceStore(
            workspaces: [emptyWorkspace, workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.closePane(PaneID(), in: WorkspaceID())
        model.closePane(PaneID(), in: emptyWorkspace.id)
        model.closePane(PaneID(), in: workspace.id)

        #expect(model.workspaces.first(where: { $0.id == emptyWorkspace.id })?.root == nil)
        #expect(model.workspaces.first(where: { $0.id == workspace.id })?.root == .leaf(pane))
    }

    @Test func `closing a focused pane restores the newest surviving pane from history`() {
        let leftPaneID = PaneID()
        let middlePaneID = PaneID()
        let rightPaneID = PaneID()
        let workspaceID = WorkspaceID()

        let target = paneFocusTargetAfterClosingPane(
            workspaceID: workspaceID,
            closedPaneID: rightPaneID,
            focusedTarget: .pane(rightPaneID),
            survivingPaneIDs: [leftPaneID, middlePaneID],
            paneFocusHistory: [leftPaneID, middlePaneID, rightPaneID],
        )

        #expect(target == .pane(middlePaneID))
    }

    @Test func `closing a nonfocused pane keeps the current focused pane when it survives`() {
        let leftPaneID = PaneID()
        let middlePaneID = PaneID()
        let rightPaneID = PaneID()
        let workspaceID = WorkspaceID()

        let target = paneFocusTargetAfterClosingPane(
            workspaceID: workspaceID,
            closedPaneID: rightPaneID,
            focusedTarget: .pane(leftPaneID),
            survivingPaneIDs: [leftPaneID, middlePaneID],
            paneFocusHistory: [middlePaneID, leftPaneID, rightPaneID],
        )

        #expect(target == .pane(leftPaneID))
    }

    @Test func `closing a focused pane skips closed history entries and uses the newest surviving pane`() {
        let leftPaneID = PaneID()
        let middlePaneID = PaneID()
        let rightPaneID = PaneID()
        let workspaceID = WorkspaceID()

        let target = paneFocusTargetAfterClosingPane(
            workspaceID: workspaceID,
            closedPaneID: rightPaneID,
            focusedTarget: .pane(rightPaneID),
            survivingPaneIDs: [leftPaneID],
            paneFocusHistory: [leftPaneID, middlePaneID, rightPaneID],
        )

        #expect(target == .pane(leftPaneID))
    }

    @Test func `closing a restored focused pane falls back to newest surviving pane when history is empty`() {
        let leftPaneID = PaneID()
        let middlePaneID = PaneID()
        let rightPaneID = PaneID()
        let workspaceID = WorkspaceID()

        let target = paneFocusTargetAfterClosingPane(
            workspaceID: workspaceID,
            closedPaneID: rightPaneID,
            focusedTarget: .pane(rightPaneID),
            survivingPaneIDs: [leftPaneID, middlePaneID],
            paneFocusHistory: [],
        )

        #expect(target == .pane(middlePaneID))
    }

    @Test func `closing the last focused pane focuses the empty workspace when inspector is visible`() {
        let paneID = PaneID()
        let workspaceID = WorkspaceID()

        let target = paneFocusTargetAfterClosingPane(
            workspaceID: workspaceID,
            closedPaneID: paneID,
            focusedTarget: .pane(paneID),
            survivingPaneIDs: [],
            paneFocusHistory: [paneID],
        )

        #expect(target == .emptyWorkspace(workspaceID))
    }

    @Test func `closing the last focused pane focuses the empty workspace when inspector is hidden`() {
        let paneID = PaneID()
        let workspaceID = WorkspaceID()

        let target = paneFocusTargetAfterClosingPane(
            workspaceID: workspaceID,
            closedPaneID: paneID,
            focusedTarget: .pane(paneID),
            survivingPaneIDs: [],
            paneFocusHistory: [paneID],
        )

        #expect(target == .emptyWorkspace(workspaceID))
    }

    @Test func `activating a window restores the newest surviving pane from history when focus is gone`() {
        let leftPaneID = PaneID()
        let rightPaneID = PaneID()

        let target = paneFocusTargetAfterActivatingWindow(
            focusedTarget: nil,
            survivingPaneIDs: [leftPaneID, rightPaneID],
            paneFocusHistory: [leftPaneID, rightPaneID],
            isInspectorVisible: true,
            hasPresentedWorkspaceModal: false,
        )

        #expect(target == .pane(rightPaneID))
    }

    @Test func `activating a window keeps the current focused pane when it still survives`() {
        let leftPaneID = PaneID()
        let rightPaneID = PaneID()

        let target = paneFocusTargetAfterActivatingWindow(
            focusedTarget: .pane(leftPaneID),
            survivingPaneIDs: [leftPaneID, rightPaneID],
            paneFocusHistory: [rightPaneID, leftPaneID],
            isInspectorVisible: true,
            hasPresentedWorkspaceModal: false,
        )

        #expect(target == .pane(leftPaneID))
    }

    @Test func `activating a window does not reclaim pane focus while a modal is presented`() {
        let paneID = PaneID()

        let target = paneFocusTargetAfterActivatingWindow(
            focusedTarget: nil,
            survivingPaneIDs: [paneID],
            paneFocusHistory: [paneID],
            isInspectorVisible: true,
            hasPresentedWorkspaceModal: true,
        )

        #expect(target == nil)
    }

    @Test func `directional pane focus prefers overlapping panes over diagonal candidates`() {
        let currentPaneID = PaneID()
        let overlappingLeftPaneID = PaneID()
        let diagonalLeftPaneID = PaneID()

        let target = directionalPaneFocus(
            from: currentPaneID,
            paneFrames: [
                currentPaneID: CGRect(x: 100, y: 100, width: 100, height: 100),
                overlappingLeftPaneID: CGRect(x: 0, y: 120, width: 80, height: 60),
                diagonalLeftPaneID: CGRect(x: 40, y: 0, width: 50, height: 40),
            ],
            direction: .left,
            history: [diagonalLeftPaneID, overlappingLeftPaneID],
        )

        #expect(target == overlappingLeftPaneID)
    }

    @Test func `directional pane focus uses the most recent history entry to break geometric ties`() {
        let currentPaneID = PaneID()
        let upperLeftPaneID = PaneID()
        let lowerLeftPaneID = PaneID()

        let target = directionalPaneFocus(
            from: currentPaneID,
            paneFrames: [
                currentPaneID: CGRect(x: 100, y: 100, width: 100, height: 100),
                upperLeftPaneID: CGRect(x: 0, y: 80, width: 80, height: 60),
                lowerLeftPaneID: CGRect(x: 0, y: 160, width: 80, height: 60),
            ],
            direction: .left,
            history: [upperLeftPaneID, lowerLeftPaneID],
        )

        #expect(target == lowerLeftPaneID)
    }

    @Test func `directional pane focus returns nil when no pane exists in that direction`() {
        let currentPaneID = PaneID()
        let rightPaneID = PaneID()

        let target = directionalPaneFocus(
            from: currentPaneID,
            paneFrames: [
                currentPaneID: CGRect(x: 100, y: 100, width: 100, height: 100),
                rightPaneID: CGRect(x: 240, y: 100, width: 100, height: 100),
            ],
            direction: .left,
            history: [rightPaneID],
        )

        #expect(target == nil)
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

    @Test func `set split fraction ignores missing workspace root and split IDs`() throws {
        let emptyWorkspace = Workspace(title: "Empty", root: nil)
        let leftPane = PaneLeaf()
        let rightPane = PaneLeaf()
        let split = PaneSplit(
            axis: .horizontal,
            fraction: 0.4,
            first: .leaf(leftPane),
            second: .leaf(rightPane),
        )
        let workspace = Workspace(title: "Workspace 1", root: .split(split))
        let model = WorkspaceStore(
            workspaces: [emptyWorkspace, workspace],
            persistence: .inMemoryForTesting(),
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.setSplitFraction(0.9, for: split.id, in: WorkspaceID())
        model.setSplitFraction(0.9, for: split.id, in: emptyWorkspace.id)
        model.setSplitFraction(0.9, for: SplitID(), in: workspace.id)

        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let updatedSplit = try #require(updatedWorkspace.root.flatMap(extractRootSplit(from:)))
        #expect(updatedSplit.fraction == 0.4)
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
