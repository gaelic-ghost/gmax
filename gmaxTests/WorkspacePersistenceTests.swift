//
//  WorkspacePersistenceTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import Testing
@testable import gmax

@MainActor
struct WorkspacePersistenceTests {
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
