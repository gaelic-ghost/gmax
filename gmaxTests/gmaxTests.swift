//
//  gmaxTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/6/26.
//

import CoreGraphics
import Testing
@testable import gmax

@MainActor
struct gmaxTests {
	@Test func renameWorkspaceUpdatesTheTitle() {
		let initialWorkspace = makeWorkspace(title: "Workspace 1")
		let model = ShellModel(
			workspaces: [initialWorkspace],
			selectedWorkspaceID: initialWorkspace.id
		)

		model.renameWorkspace(initialWorkspace.id, to: "Primary Shell")

		#expect(model.workspaces[0].title == "Primary Shell")
	}

	@Test func duplicateWorkspaceClonesTheLayoutAndSelectsTheCopy() {
		let leftPane = PaneLeaf()
		let rightPane = PaneLeaf()
		let workspace = Workspace(
			title: "Workspace 1",
			root: .split(
				PaneSplit(
					axis: .horizontal,
					fraction: 0.4,
					first: .leaf(leftPane),
					second: .leaf(rightPane)
				)
			),
			focusedPaneID: rightPane.id
		)
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id
		)

		model.duplicateWorkspace(workspace.id)

		#expect(model.workspaces.count == 2)
		#expect(model.selectedWorkspace?.id == model.workspaces[1].id)
		#expect(model.workspaces[1].title == "Workspace 1 Copy")

		let originalLeaves = Set(workspace.paneLeaves.map(\.id))
		let duplicatedWorkspace = model.workspaces[1]
		let duplicatedLeaves = Set(duplicatedWorkspace.paneLeaves.map(\.id))
		let duplicatedSessions = Set(duplicatedWorkspace.paneLeaves.map(\.sessionID))

		#expect(duplicatedWorkspace.paneCount == workspace.paneCount)
		#expect(originalLeaves.isDisjoint(with: duplicatedLeaves))
		#expect(Set(workspace.paneLeaves.map(\.sessionID)).isDisjoint(with: duplicatedSessions))
	}

	@Test func deleteWorkspaceRemovesItAndSelectsTheNeighbor() {
		let firstWorkspace = makeWorkspace(title: "Workspace 1")
		let secondWorkspace = makeWorkspace(title: "Workspace 2")
		let model = ShellModel(
			workspaces: [firstWorkspace, secondWorkspace],
			selectedWorkspaceID: firstWorkspace.id
		)

		model.deleteWorkspace(firstWorkspace.id)

		#expect(model.workspaces.count == 1)
		#expect(model.workspaces[0].id == secondWorkspace.id)
		#expect(model.selectedWorkspace?.id == secondWorkspace.id)
	}

	@Test func deleteWorkspaceDoesNothingWhenItIsTheLastWorkspace() {
		let workspace = makeWorkspace(title: "Workspace 1")
		let model = ShellModel(
			workspaces: [workspace],
			selectedWorkspaceID: workspace.id
		)

		model.deleteWorkspace(workspace.id)

		#expect(model.workspaces.count == 1)
		#expect(model.selectedWorkspace?.id == workspace.id)
	}

	@Test func undoCloseWorkspaceRestoresTheWorkspaceAndItsLaunchDirectory() throws {
		let firstWorkspace = makeWorkspace(title: "Workspace 1")
		let secondWorkspace = makeWorkspace(title: "Workspace 2")
		let persistence = ShellPersistenceController.inMemoryForTesting()
		let launchContextBuilder = makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
		let model = ShellModel(
			workspaces: [firstWorkspace, secondWorkspace],
			selectedWorkspaceID: firstWorkspace.id,
			persistence: persistence,
			launchContextBuilder: launchContextBuilder
		)

		let firstPane = try #require(firstWorkspace.root?.firstLeaf())
		let firstSession = model.sessions.ensureSession(id: firstPane.sessionID)
		firstSession.currentDirectory = "/tmp/restored-workspace"

		_ = model.closeWorkspace(firstWorkspace.id)
		let reopenedWorkspaceID = model.undoCloseWorkspace()

		#expect(model.workspaces.count == 2)
		#expect(reopenedWorkspaceID == firstWorkspace.id)
		#expect(model.selectedWorkspace?.id == firstWorkspace.id)

		let reopenedWorkspace = try #require(model.workspace(for: firstWorkspace.id))
		let reopenedPane = try #require(reopenedWorkspace.root?.firstLeaf())
		let reopenedSession = try #require(model.sessions.session(for: reopenedPane.sessionID))
		#expect(reopenedSession.currentDirectory == "/tmp/restored-workspace")
	}

	@Test func saveAndOpenSavedWorkspaceRestoreSessionMetadataAndTranscript() throws {
		let workspace = makeWorkspace(title: "Workspace 1")
		let persistence = ShellPersistenceController.inMemoryForTesting()
		let launchContextBuilder = makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
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

	@Test func closeWorkspaceToLibraryCreatesAReusableSnapshotAndSelectsTheNeighbor() throws {
		let firstWorkspace = makeWorkspace(title: "Workspace 1")
		let secondWorkspace = makeWorkspace(title: "Workspace 2")
		let persistence = ShellPersistenceController.inMemoryForTesting()
		let launchContextBuilder = makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
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

	private func makeWorkspace(title: String) -> Workspace {
		let pane = PaneLeaf()
		return Workspace(
			title: title,
			root: .leaf(pane),
			focusedPaneID: pane.id
		)
	}

	private func makeLaunchContextBuilder(defaultCurrentDirectory: String) -> TerminalLaunchContextBuilder {
		TerminalLaunchContextBuilder(
			shellExecutable: "/bin/zsh",
			shellArguments: ["-l"],
			baseEnvironment: ["TERM": "xterm-256color"],
			defaultCurrentDirectory: defaultCurrentDirectory
		)
	}
}
