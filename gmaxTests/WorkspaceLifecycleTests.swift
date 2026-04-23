//
//  WorkspaceLifecycleTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreGraphics
@testable import gmax
import Testing

@MainActor
struct WorkspaceLifecycleTests {
    @Test func `rename workspace updates the title`() {
        let initialWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            workspaces: [initialWorkspace],
        )

        model.renameWorkspace(initialWorkspace.id, to: "Primary Shell")

        #expect(model.workspaces[0].title == "Primary Shell")
    }

    @Test func `duplicate workspace clones the layout and selects the copy`() throws {
        let leftPane = PaneLeaf()
        let rightPane = PaneLeaf()
        let workspace = Workspace(
            title: "Workspace 1",
            root: .split(
                PaneSplit(
                    axis: .horizontal,
                    fraction: 0.4,
                    first: .leaf(leftPane),
                    second: .leaf(rightPane),
                ),
            ),
        )
        let model = WorkspaceStore(
            workspaces: [workspace],
        )

        let duplicatedWorkspaceID = try #require(model.duplicateWorkspace(workspace.id))

        #expect(model.workspaces.count == 2)
        #expect(duplicatedWorkspaceID == model.workspaces[1].id)
        #expect(model.workspaces[1].title == "Workspace 1 Copy")

        let originalLeaves = Set(workspace.paneLeaves.map(\.id))
        let duplicatedWorkspace = model.workspaces[1]
        let duplicatedLeaves = Set(duplicatedWorkspace.paneLeaves.map(\.id))
        let duplicatedSessions = Set(duplicatedWorkspace.paneLeaves.map(\.sessionID))

        #expect(duplicatedWorkspace.paneCount == workspace.paneCount)
        #expect(originalLeaves.isDisjoint(with: duplicatedLeaves))
        #expect(Set(workspace.paneLeaves.map(\.sessionID)).isDisjoint(with: duplicatedSessions))
    }

    @Test func `delete workspace removes it and selects the neighbor`() {
        let firstWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let secondWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(workspaces: [firstWorkspace, secondWorkspace])

        model.deleteWorkspace(firstWorkspace.id)

        #expect(model.workspaces.count == 1)
        #expect(model.workspaces[0].id == secondWorkspace.id)
    }

    @Test func `delete workspace does nothing when it is the last workspace`() {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(workspaces: [workspace])

        model.deleteWorkspace(workspace.id)

        #expect(model.workspaces.count == 1)
        #expect(model.workspaces[0].id == workspace.id)
    }

    @Test func `undo close workspace restores the workspace and its launch directory`() throws {
        let firstWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let secondWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
        let model = WorkspaceStore(
            workspaces: [firstWorkspace, secondWorkspace],
            persistence: persistence,
            launchContextBuilder: launchContextBuilder,
        )

        let firstPane = try #require(firstWorkspace.root?.firstLeaf())
        let firstSession = model.sessions.ensureSession(id: firstPane.sessionID)
        firstSession.currentDirectory = "/tmp/restored-workspace"

        _ = model.closeWorkspace(firstWorkspace.id)
        let reopenedWorkspaceID = model.undoCloseWorkspace()

        #expect(model.workspaces.count == 2)
        #expect(reopenedWorkspaceID == firstWorkspace.id)

        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == firstWorkspace.id }))
        let reopenedPane = try #require(reopenedWorkspace.root?.firstLeaf())
        let reopenedSession = try #require(model.sessions.session(for: reopenedPane.sessionID))
        #expect(reopenedSession.currentDirectory == "/tmp/restored-workspace")
    }

    @Test func `close workspace removes the last workspace without asking to close the window`() {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(workspaces: [workspace])

        let nextSelectedWorkspaceID = model.closeWorkspace(workspace.id)

        #expect(nextSelectedWorkspaceID == nil)
        #expect(model.workspaces.isEmpty)
    }

    @Test func `default workspace store bootstrap does not require launching A shell process`() {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()

        let model = WorkspaceStore(
            persistence: persistence,
        )

        #expect(model.workspaces.count == 1)
        #expect(model.workspaces[0].title == "Workspace 1")
    }

    @Test func `workspace store loads the durable selected workspace for its window`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let firstWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let secondWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let seedStore = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [firstWorkspace, secondWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        seedStore.persistedSelectedWorkspaceID = secondWorkspace.id
        seedStore.persistSceneStateNow(reason: .unitTestImmediateFlush)

        let restoredStore = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        #expect(restoredStore.persistedSelectedWorkspaceID == secondWorkspace.id)
    }
}
