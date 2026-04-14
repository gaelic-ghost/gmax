//
//  WorkspacePersistenceTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreGraphics
import Testing
@testable import gmax

@MainActor
struct WorkspacePersistenceTests {
	@Test func saveAndOpenSavedWorkspaceRestoreComplexLayoutFocusedPaneAndSessionMetadata() throws {
		let leftPane = PaneLeaf()
		let topRightPane = PaneLeaf()
		let bottomRightPane = PaneLeaf()
		let workspace = Workspace(
			title: "Workspace 1",
			root: .split(
				PaneSplit(
					axis: .horizontal,
					fraction: 0.4,
					first: .leaf(leftPane),
					second: .split(
						PaneSplit(
							axis: .vertical,
							fraction: 0.65,
							first: .leaf(topRightPane),
							second: .leaf(bottomRightPane)
						)
					)
				)
			),
			focusedPaneID: bottomRightPane.id
		)
		let persistence = ShellPersistenceController.inMemoryForTesting()
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id,
			persistence: persistence,
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		let originalLeaves = workspace.paneLeaves
		let originalFocusedPath = try #require(
			leafPaths(in: workspace.root).first(where: { $0.leaf.id == bottomRightPane.id })?.path
		)
		let expectedSignature = try #require(workspace.root.map(nodeSignature(from:)))

		let metadataBySessionID: [TerminalSessionID: (title: String, directory: String, transcript: String)] = [
			leftPane.sessionID: ("Left Shell", "/tmp/layout/left", "printf left\n"),
			topRightPane.sessionID: ("Top Right Shell", "/tmp/layout/top-right", "printf top-right\n"),
			bottomRightPane.sessionID: ("Bottom Right Shell", "/tmp/layout/bottom-right", "printf bottom-right\n")
		]

		for leaf in originalLeaves {
			let session = model.sessions.ensureSession(id: leaf.sessionID)
			let metadata = try #require(metadataBySessionID[leaf.sessionID])
			session.title = metadata.title
			session.currentDirectory = metadata.directory
		}

		let summary = try #require(
			model.saveWorkspaceToLibrary(
				workspace.id,
				transcriptsBySessionID: Dictionary(
					uniqueKeysWithValues: metadataBySessionID.map { ($0.key, $0.value.transcript) }
				)
			)
		)

		let reopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
		let reopenedWorkspace = try #require(model.workspace(for: reopenedWorkspaceID))
		let reopenedRoot = try #require(reopenedWorkspace.root)
		let reopenedLeaves = reopenedWorkspace.paneLeaves
		let reopenedFocusedPath = try #require(
			leafPaths(in: reopenedRoot).first(where: { $0.leaf.id == reopenedWorkspace.focusedPaneID })?.path
		)

		#expect(summary.paneCount == 3)
		#expect(nodeSignature(from: reopenedRoot) == expectedSignature)
		#expect(reopenedWorkspace.paneCount == 3)
		#expect(reopenedFocusedPath == originalFocusedPath)
		#expect(reopenedLeaves.count == originalLeaves.count)

		for (index, originalLeaf) in originalLeaves.enumerated() {
			let reopenedLeaf = reopenedLeaves[index]
			let restoredSession = try #require(model.sessions.session(for: reopenedLeaf.sessionID))
			let metadata = try #require(metadataBySessionID[originalLeaf.sessionID])
			#expect(restoredSession.title == metadata.title)
			#expect(restoredSession.currentDirectory == metadata.directory)
			#expect(restoredSession.consumeRestoredTranscript() == metadata.transcript)
		}
	}

	@Test func saveAndOpenSavedWorkspaceRestoreSessionMetadataAndTranscript() throws {
		let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
		let persistence = ShellPersistenceController.inMemoryForTesting()
		let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id,
			persistence: persistence,
			launchContextBuilder: launchContextBuilder
		)

		let pane = try #require(workspace.root?.firstLeaf())
		let session = model.sessions.ensureSession(id: pane.sessionID)
		session.title = "Build Shell"
		session.currentDirectory = "/tmp/workspace-library"

		let summary = try #require(
			model.saveWorkspaceToLibrary(
				workspace.id,
				transcriptsBySessionID: [pane.sessionID: "$ pwd\n/tmp/workspace-library\n"]
			)
		)

		let reopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
		let reopenedWorkspace = try #require(model.workspace(for: reopenedWorkspaceID))
		let reopenedPane = try #require(reopenedWorkspace.root?.firstLeaf())
		let reopenedSession = try #require(model.sessions.session(for: reopenedPane.sessionID))

		#expect(model.listSavedWorkspaceSnapshots().count == 1)
		#expect(reopenedWorkspace.title.starts(with: "Workspace 1"))
		#expect(reopenedSession.title == "Build Shell")
		#expect(reopenedSession.currentDirectory == "/tmp/workspace-library")
		#expect(reopenedSession.consumeRestoredTranscript() == "$ pwd\n/tmp/workspace-library\n")
	}

	@Test func savedWorkspaceSnapshotCanBeOpenedRepeatedlyWithoutMutatingTheStoredLayout() throws {
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
							fraction: 0.55,
							first: .leaf(topRightPane),
							second: .leaf(bottomRightPane)
						)
					)
				)
			),
			focusedPaneID: topRightPane.id
		)
		let persistence = ShellPersistenceController.inMemoryForTesting()
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id,
			persistence: persistence,
			launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		)

		let expectedSignature = try #require(workspace.root.map(nodeSignature(from:)))
		let snapshotTranscripts: [TerminalSessionID: String] = [
			leftPane.sessionID: "echo left\n",
			topRightPane.sessionID: "echo top-right\n",
			bottomRightPane.sessionID: "echo bottom-right\n"
		]

		let summary = try #require(
			model.saveWorkspaceToLibrary(
				workspace.id,
				transcriptsBySessionID: snapshotTranscripts
			)
		)

		let firstReopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
		_ = try #require(model.workspace(for: firstReopenedWorkspaceID))
		model.setCurrentWorkspaceID(firstReopenedWorkspaceID)
		model.splitFocusedPane(.right)
		let mutatedFirstWorkspace = try #require(model.workspace(for: firstReopenedWorkspaceID))
		#expect(mutatedFirstWorkspace.paneCount == 4)

		let secondReopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
		let secondReopenedWorkspace = try #require(model.workspace(for: secondReopenedWorkspaceID))
		let secondReopenedRoot = try #require(secondReopenedWorkspace.root)
		let secondReopenedLeaves = secondReopenedWorkspace.paneLeaves

		#expect(model.listSavedWorkspaceSnapshots().count == 1)
		#expect(nodeSignature(from: secondReopenedRoot) == expectedSignature)
		#expect(secondReopenedWorkspace.paneCount == 3)
		#expect(secondReopenedWorkspace.title != mutatedFirstWorkspace.title)

		for (index, originalLeaf) in workspace.paneLeaves.enumerated() {
			let reopenedLeaf = secondReopenedLeaves[index]
			let restoredSession = try #require(model.sessions.session(for: reopenedLeaf.sessionID))
			#expect(restoredSession.consumeRestoredTranscript() == snapshotTranscripts[originalLeaf.sessionID])
		}
	}

	@Test func closeWorkspaceToLibraryCreatesAReusableSnapshotAndSelectsTheNeighbor() throws {
		let firstWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
		let secondWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
		let persistence = ShellPersistenceController.inMemoryForTesting()
		let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		let model = ShellModel(
			workspaces: [firstWorkspace, secondWorkspace],
			selectedWorkspaceID: firstWorkspace.id,
			persistence: persistence,
			launchContextBuilder: launchContextBuilder
		)

		let firstPane = try #require(firstWorkspace.root?.firstLeaf())
		let outcome = model.closeWorkspaceToLibrary(
			firstWorkspace.id,
			transcriptsBySessionID: [firstPane.sessionID: "echo library-close\n"]
		)

		let snapshot = try #require(model.listSavedWorkspaceSnapshots().first)
		let reopenedWorkspaceID = try #require(model.openSavedWorkspace(snapshot.id))
		let reopenedWorkspace = try #require(model.workspace(for: reopenedWorkspaceID))

		#expect(outcome.result == .closedWorkspace)
		#expect(outcome.nextSelectedWorkspaceID == secondWorkspace.id)
		#expect(model.workspaces.count == 2)
		#expect(model.selectedWorkspace?.id == reopenedWorkspaceID)
		#expect(reopenedWorkspace.title == "Workspace 1")
	}
}

private indirect enum PaneNodeSignature: Equatable {
	case leaf
	case split(axis: PaneSplit.Axis, fraction: Double, first: PaneNodeSignature, second: PaneNodeSignature)
}

private func nodeSignature(from node: PaneNode) -> PaneNodeSignature {
	switch node {
		case .leaf:
			return .leaf
		case .split(let split):
			return .split(
				axis: split.axis,
				fraction: Double(split.fraction),
				first: nodeSignature(from: split.first),
				second: nodeSignature(from: split.second)
			)
	}
}

private func leafPaths(in node: PaneNode?, path: [Int] = []) -> [(leaf: PaneLeaf, path: [Int])] {
	guard let node else {
		return []
	}

	switch node {
		case .leaf(let leaf):
			return [(leaf, path)]
		case .split(let split):
			return leafPaths(in: split.first, path: path + [0]) + leafPaths(in: split.second, path: path + [1])
	}
}
