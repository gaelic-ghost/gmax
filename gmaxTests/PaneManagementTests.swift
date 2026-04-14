//
//  PaneManagementTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreGraphics
import Testing
@testable import gmax

@MainActor
struct PaneManagementTests {
	@Test func splitFocusedPaneInheritsTheLaunchDirectoryAndMovesFocus() throws {
		let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
		let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id,
			persistence: .inMemoryForTesting(),
			launchContextBuilder: launchContextBuilder
		)

		let originalPane = try #require(workspace.root?.firstLeaf())
		let originalSession = model.sessions.ensureSession(id: originalPane.sessionID)
		originalSession.currentDirectory = "/tmp/inherited-pane"

		model.splitFocusedPane(.down)

		let updatedWorkspace = try #require(model.selectedWorkspace)
		let root = try #require(updatedWorkspace.root)
		let split = try #require(extractRootSplit(from: root))
		let firstLeaf = try #require(extractRootLeaf(from: split.first))
		let secondLeaf = try #require(extractRootLeaf(from: split.second))
		let insertedSession = try #require(model.sessions.session(for: secondLeaf.sessionID))

		#expect(updatedWorkspace.paneCount == 2)
		#expect(split.axis == PaneSplit.Axis.vertical)
		#expect(firstLeaf.id == originalPane.id)
		#expect(updatedWorkspace.focusedPaneID == secondLeaf.id)
		#expect(insertedSession.currentDirectory == "/tmp/inherited-pane")
	}

	@Test func closePaneFallsBackToTheNextSurvivingPaneAndRemovesTheSession() throws {
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
							second: .leaf(bottomRightPane)
						)
					)
				)
			),
			focusedPaneID: topRightPane.id
		)
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id,
			persistence: .inMemoryForTesting(),
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		_ = model.sessions.ensureSession(id: leftPane.sessionID)
		_ = model.sessions.ensureSession(id: topRightPane.sessionID)
		_ = model.sessions.ensureSession(id: bottomRightPane.sessionID)

		model.focusPane(leftPane.id, in: workspace.id)
		model.focusPane(topRightPane.id, in: workspace.id)
		model.updatePaneFrames(
			[
				leftPane.id: CGRect(x: 0, y: 0, width: 300, height: 600),
				topRightPane.id: CGRect(x: 300, y: 0, width: 300, height: 300),
				bottomRightPane.id: CGRect(x: 300, y: 300, width: 300, height: 300)
			],
			in: workspace.id
		)

		model.closePane(topRightPane.id, in: workspace.id)

		let updatedWorkspace = try #require(model.workspace(for: workspace.id))
		let framePaneIDs = Set(model.paneFramesByWorkspace[workspace.id]?.map(\.key) ?? [])
		#expect(updatedWorkspace.focusedPaneID == bottomRightPane.id)
		#expect(updatedWorkspace.paneLeaves.map(\.id) == [leftPane.id, bottomRightPane.id])
		#expect(model.sessions.session(for: topRightPane.sessionID) == nil)
		#expect(framePaneIDs == Set([leftPane.id, bottomRightPane.id]))
		#expect(model.paneFocusHistoryByWorkspace[workspace.id] == [leftPane.id, bottomRightPane.id])
	}

	@Test func setSplitFractionUpdatesTheWorkspaceTree() throws {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		let split = PaneSplit(
			axis: .horizontal,
			fraction: 0.4,
			first: .leaf(leftPane),
			second: .leaf(rightPane)
		)
		let workspace = Workspace(
			title: "Workspace 1",
			root: .split(split),
			focusedPaneID: leftPane.id
		)
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id,
			persistence: .inMemoryForTesting(),
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		model.setSplitFraction(0.65, for: split.id, in: workspace.id)

		let updatedWorkspace = try #require(model.workspace(for: workspace.id))
		let updatedSplit = try #require(updatedWorkspace.root.flatMap(extractRootSplit(from:)))
		#expect(updatedSplit.fraction == 0.65)
	}

	@Test func movePaneFocusUsesDirectionalGeometryWhenPaneFramesExist() throws {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		let workspace = Workspace(
			title: "Workspace 1",
			root: .split(
				PaneSplit(
					axis: .horizontal,
					fraction: 0.5,
					first: .leaf(leftPane),
					second: .leaf(rightPane)
				)
			),
			focusedPaneID: leftPane.id
		)
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id,
			persistence: .inMemoryForTesting(),
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		model.updatePaneFrames(
			[
				leftPane.id: CGRect(x: 0, y: 0, width: 300, height: 600),
				rightPane.id: CGRect(x: 300, y: 0, width: 300, height: 600)
			],
			in: workspace.id
		)

		model.movePaneFocus(.right)
		#expect(model.selectedWorkspace?.focusedPaneID == rightPane.id)

		model.movePaneFocus(.left)
		#expect(model.selectedWorkspace?.focusedPaneID == leftPane.id)
	}
}

private func extractRootSplit(from node: PaneNode) -> PaneSplit? {
	guard case .split(let split) = node else {
		return nil
	}
	return split
}

private func extractRootLeaf(from node: PaneNode) -> PaneLeaf? {
	guard case .leaf(let leaf) = node else {
		return nil
	}
	return leaf
}
