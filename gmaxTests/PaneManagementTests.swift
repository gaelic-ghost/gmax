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
	@Test func splitFocusedPaneTwiceCreatesANestedTreeAndTracksTheNewestPane() throws {
		let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
		let model = ShellModel(
			workspaces: [workspace],
			persistence: .inMemoryForTesting(),
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		let originalPane = try #require(workspace.root?.firstLeaf())
		let originalSession = model.sessions.ensureSession(id: originalPane.sessionID)
		originalSession.currentDirectory = "/tmp/nested-split"

		model.splitFocusedPane(in: workspace.id, .right)
		let firstInsertedPaneID = try #require(model.workspace(for: workspace.id)?.focusedPaneID)
		model.splitFocusedPane(in: workspace.id, .down)

		let updatedWorkspace = try #require(model.workspace(for: workspace.id))
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
		#expect(updatedWorkspace.focusedPaneID == nestedSecondLeaf.id)
		#expect(model.paneFocusHistoryByWorkspace[workspace.id] == [originalPane.id, firstInsertedPaneID, nestedSecondLeaf.id])
		#expect(newestSession.currentDirectory == "/tmp/nested-split")
	}

	@Test func splitFocusedPaneInheritsTheLaunchDirectoryAndMovesFocus() throws {
		let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
		let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		let model = ShellModel(
			workspaces: [workspace],
			persistence: .inMemoryForTesting(),
			launchContextBuilder: launchContextBuilder
		)

		let originalPane = try #require(workspace.root?.firstLeaf())
		let originalSession = model.sessions.ensureSession(id: originalPane.sessionID)
		originalSession.currentDirectory = "/tmp/inherited-pane"

		model.splitFocusedPane(in: workspace.id, .down)

		let updatedWorkspace = try #require(model.workspace(for: workspace.id))
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

	@Test func closeFocusedPaneLeavesAnEmptyWorkspaceWhenItWasTheLastPane() throws {
		let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
		let model = ShellModel(
			workspaces: [workspace],
			persistence: .inMemoryForTesting(),
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		let pane = try #require(workspace.root?.firstLeaf())
		_ = model.sessions.ensureSession(id: pane.sessionID)
		model.updatePaneFrames([pane.id: CGRect(x: 0, y: 0, width: 400, height: 300)], in: workspace.id)

		let outcome = model.closeFocusedPane(in: workspace.id)
		let updatedWorkspace = try #require(model.workspace(for: workspace.id))

		#expect(outcome.result == .closedPane)
		#expect(outcome.nextSelectedWorkspaceID == workspace.id)
		#expect(updatedWorkspace.root == nil)
		#expect(updatedWorkspace.focusedPaneID == nil)
		#expect(updatedWorkspace.paneCount == 0)
		#expect(model.sessions.session(for: pane.sessionID) == nil)
		#expect(model.paneFramesByWorkspace[workspace.id] == nil)
		#expect(model.paneFocusHistoryByWorkspace[workspace.id] == nil)
	}

	@Test func closingTheFocusedPaneAfterMultipleSplitsPrefersTheMostRecentSurvivingFocus() throws {
		let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
		let model = ShellModel(
			workspaces: [workspace],
			persistence: .inMemoryForTesting(),
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		let originalPane = try #require(workspace.root?.firstLeaf())
		model.splitFocusedPane(in: workspace.id, .right)
		let rightPaneID = try #require(model.workspace(for: workspace.id)?.focusedPaneID)
		model.splitFocusedPane(in: workspace.id, .down)
		let bottomRightPaneID = try #require(model.workspace(for: workspace.id)?.focusedPaneID)
		let bottomRightSessionID = try #require(
			model.workspace(for: workspace.id)?.paneLeaves.first(where: { $0.id == bottomRightPaneID })?.sessionID
		)

		model.focusPane(originalPane.id, in: workspace.id)
		model.focusPane(rightPaneID, in: workspace.id)
		model.focusPane(bottomRightPaneID, in: workspace.id)
		model.updatePaneFrames(
			[
				originalPane.id: CGRect(x: 0, y: 0, width: 300, height: 600),
				rightPaneID: CGRect(x: 300, y: 0, width: 300, height: 300),
				bottomRightPaneID: CGRect(x: 300, y: 300, width: 300, height: 300)
			],
			in: workspace.id
		)

		model.closePane(bottomRightPaneID, in: workspace.id)

		let updatedWorkspace = try #require(model.workspace(for: workspace.id))
		let survivingLeaves = updatedWorkspace.paneLeaves
		let framePaneIDs = Set(model.paneFramesByWorkspace[workspace.id]?.map(\.key) ?? [])

		#expect(updatedWorkspace.focusedPaneID == rightPaneID)
		#expect(survivingLeaves.map(\.id) == [originalPane.id, rightPaneID])
		#expect(framePaneIDs == Set([originalPane.id, rightPaneID]))
		#expect(model.sessions.session(for: bottomRightSessionID) == nil)
		#expect(model.paneFocusHistoryByWorkspace[workspace.id] == [originalPane.id, rightPaneID])
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

		model.movePaneFocus(.right, in: workspace.id)
		#expect(model.workspace(for: workspace.id)?.focusedPaneID == rightPane.id)

		model.movePaneFocus(.left, in: workspace.id)
		#expect(model.workspace(for: workspace.id)?.focusedPaneID == leftPane.id)
	}

	@Test func movePaneFocusChoosesTheClosestCandidateInTheRequestedDirection() throws {
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
			focusedPaneID: leftPane.id
		)
		let model = ShellModel(
			workspaces: [workspace],
			persistence: .inMemoryForTesting(),
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		model.updatePaneFrames(
			[
				leftPane.id: CGRect(x: 0, y: 0, width: 300, height: 600),
				topRightPane.id: CGRect(x: 300, y: 0, width: 300, height: 260),
				bottomRightPane.id: CGRect(x: 300, y: 260, width: 300, height: 340)
			],
			in: workspace.id
		)

		model.movePaneFocus(.right, in: workspace.id)
		#expect(model.workspace(for: workspace.id)?.focusedPaneID == bottomRightPane.id)

		model.movePaneFocus(.up, in: workspace.id)
		#expect(model.workspace(for: workspace.id)?.focusedPaneID == topRightPane.id)
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
