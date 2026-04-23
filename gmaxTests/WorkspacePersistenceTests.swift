//
//  WorkspacePersistenceTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreData
import CoreGraphics
@testable import gmax
import Testing

@MainActor
struct WorkspacePersistenceTests {
    @Test func `persistSceneStateNow writes live workspace changes without waiting for debounce`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [TestSupport.makeWorkspace(title: "Workspace 1")],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let workspaceID = try #require(model.workspaces.first?.id)
        model.renameWorkspace(workspaceID, to: "Renamed Workspace")
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)

        let restoredTitles = persistence.loadWorkspaces(for: sceneIdentity).map(\.title)
        #expect(restoredTitles == ["Renamed Workspace"])
    }

    @Test func `persistSceneStateNow writes the durable selected workspace for a window`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let firstWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let secondWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [firstWorkspace, secondWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.persistedSelectedWorkspaceID = secondWorkspace.id
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)

        let restoredWindowState = try #require(persistence.loadWindowState(for: sceneIdentity))
        #expect(restoredWindowState.selectedWorkspaceID == secondWorkspace.id)
    }

    @Test func `save and open saved workspace restore large nested layout across five panes`() throws {
        let leftTopPane = PaneLeaf()
        let leftBottomPane = PaneLeaf()
        let rightTopPane = PaneLeaf()
        let rightMiddlePane = PaneLeaf()
        let rightBottomPane = PaneLeaf()
        let workspace = Workspace(
            title: "Workspace 1",
            root: .split(
                PaneSplit(
                    axis: .horizontal,
                    fraction: 0.42,
                    first: .split(
                        PaneSplit(
                            axis: .vertical,
                            fraction: 0.38,
                            first: .leaf(leftTopPane),
                            second: .leaf(leftBottomPane),
                        ),
                    ),
                    second: .split(
                        PaneSplit(
                            axis: .vertical,
                            fraction: 0.48,
                            first: .leaf(rightTopPane),
                            second: .split(
                                PaneSplit(
                                    axis: .horizontal,
                                    fraction: 0.57,
                                    first: .leaf(rightMiddlePane),
                                    second: .leaf(rightBottomPane),
                                ),
                            ),
                        ),
                    ),
                ),
            ),
        )
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let siblingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            workspaces: [workspace, siblingWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let originalLeaves = workspace.paneLeaves
        let expectedSignature = try #require(workspace.root.map(nodeSignature(from:)))

        let metadataBySessionID: [TerminalSessionID: (title: String, directory: String, transcript: String)] = [
            leftTopPane.sessionID: ("Left Top Shell", "/tmp/layout/left-top", "printf left-top\n"),
            leftBottomPane.sessionID: ("Left Bottom Shell", "/tmp/layout/left-bottom", "printf left-bottom\n"),
            rightTopPane.sessionID: ("Right Top Shell", "/tmp/layout/right-top", "printf right-top\n"),
            rightMiddlePane.sessionID: ("Right Middle Shell", "/tmp/layout/right-middle", "printf right-middle\n"),
            rightBottomPane.sessionID: ("Right Bottom Shell", "/tmp/layout/right-bottom", "printf right-bottom\n"),
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
                    uniqueKeysWithValues: metadataBySessionID.map { ($0.key, $0.value.transcript) },
                ),
            ),
        )
        model.deleteWorkspace(workspace.id)
        let reopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedRoot = try #require(reopenedWorkspace.root)
        let reopenedLeaves = reopenedWorkspace.paneLeaves

        #expect(summary.paneCount == 5)
        #expect(reopenedWorkspaceID == workspace.id)
        #expect(nodeSignature(from: reopenedRoot) == expectedSignature)
        #expect(reopenedWorkspace.paneCount == 5)
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

    @Test func `save and open saved workspace restore complex layout focused pane and session metadata`() throws {
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
                            second: .leaf(bottomRightPane),
                        ),
                    ),
                ),
            ),
        )
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let siblingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            workspaces: [workspace, siblingWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let originalLeaves = workspace.paneLeaves
        let expectedSignature = try #require(workspace.root.map(nodeSignature(from:)))

        let metadataBySessionID: [TerminalSessionID: (title: String, directory: String, transcript: String)] = [
            leftPane.sessionID: ("Left Shell", "/tmp/layout/left", "printf left\n"),
            topRightPane.sessionID: ("Top Right Shell", "/tmp/layout/top-right", "printf top-right\n"),
            bottomRightPane.sessionID: ("Bottom Right Shell", "/tmp/layout/bottom-right", "printf bottom-right\n"),
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
                    uniqueKeysWithValues: metadataBySessionID.map { ($0.key, $0.value.transcript) },
                ),
            ),
        )

        model.deleteWorkspace(workspace.id)
        let reopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedRoot = try #require(reopenedWorkspace.root)
        let reopenedLeaves = reopenedWorkspace.paneLeaves

        #expect(summary.paneCount == 3)
        #expect(reopenedWorkspaceID == workspace.id)
        #expect(nodeSignature(from: reopenedRoot) == expectedSignature)
        #expect(reopenedWorkspace.paneCount == 3)
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

    @Test func `save and open saved workspace restore session metadata and transcript`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
        let siblingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            workspaces: [workspace, siblingWorkspace],
            persistence: persistence,
            launchContextBuilder: launchContextBuilder,
        )

        let pane = try #require(workspace.root?.firstLeaf())
        let session = model.sessions.ensureSession(id: pane.sessionID)
        session.title = "Build Shell"
        session.currentDirectory = "/tmp/workspace-library"

        let summary = try #require(
            model.saveWorkspaceToLibrary(
                workspace.id,
                transcriptsBySessionID: [pane.sessionID: "$ pwd\n/tmp/workspace-library\n"],
            ),
        )

        model.deleteWorkspace(workspace.id)
        let reopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedPane = try #require(reopenedWorkspace.root?.firstLeaf())
        let reopenedSession = try #require(model.sessions.session(for: reopenedPane.sessionID))

        #expect(model.listSavedWorkspaces().isEmpty)
        #expect(reopenedWorkspaceID == workspace.id)
        #expect(reopenedWorkspace.title.starts(with: "Workspace 1"))
        #expect(reopenedSession.title == "Build Shell")
        #expect(reopenedSession.currentDirectory == "/tmp/workspace-library")
        #expect(reopenedSession.consumeRestoredTranscript() == "$ pwd\n/tmp/workspace-library\n")
    }

    @Test func `opening a saved workspace while it is already live reuses the same identity and does not duplicate it`() throws {
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
                            second: .leaf(bottomRightPane),
                        ),
                    ),
                ),
            ),
        )
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let expectedSignature = try #require(workspace.root.map(nodeSignature(from:)))
        let summary = try #require(
            model.saveWorkspaceToLibrary(
                workspace.id,
                transcriptsBySessionID: [
                    leftPane.sessionID: "echo left\n",
                    topRightPane.sessionID: "echo top-right\n",
                    bottomRightPane.sessionID: "echo bottom-right\n",
                ],
            ),
        )

        let reopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedRoot = try #require(reopenedWorkspace.root)

        #expect(reopenedWorkspaceID == workspace.id)
        #expect(model.workspaces.count == 1)
        #expect(model.listSavedWorkspaces().isEmpty)
        #expect(nodeSignature(from: reopenedRoot) == expectedSignature)
    }

    @Test func `open saved workspace returns nil when saved workspace pane tree is corrupted`() throws {
        let leftPane = PaneLeaf()
        let rightPane = PaneLeaf()
        let workspace = Workspace(
            title: "Workspace 1",
            root: .split(
                PaneSplit(
                    axis: .horizontal,
                    fraction: 0.5,
                    first: .leaf(leftPane),
                    second: .leaf(rightPane),
                ),
            ),
        )
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let siblingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            workspaces: [workspace, siblingWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let summary = try #require(model.saveWorkspaceToLibrary(workspace.id))
        let context = persistence.container.viewContext

        let savedWorkspacePlacement = try #require(try fetchSavedWorkspacePlacement(id: summary.id, in: context))
        let rootNode = try #require(savedWorkspacePlacement.workspace?.rootNode)
        rootNode.firstChild = nil
        try context.save()

        model.deleteWorkspace(workspace.id)
        let reopenedWorkspaceID = model.openSavedWorkspace(summary.id)

        #expect(reopenedWorkspaceID == nil)
        #expect(model.workspaces.count == 1)
        #expect(model.listSavedWorkspaces().count == 1)
    }

    @Test func `open saved workspace falls back to default launch configuration when A pane session snapshot is missing`() throws {
        let leftPane = PaneLeaf()
        let rightPane = PaneLeaf()
        let workspace = Workspace(
            title: "Workspace 1",
            root: .split(
                PaneSplit(
                    axis: .horizontal,
                    fraction: 0.5,
                    first: .leaf(leftPane),
                    second: .leaf(rightPane),
                ),
            ),
        )
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/default-fallback")
        let siblingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            workspaces: [workspace, siblingWorkspace],
            persistence: persistence,
            launchContextBuilder: launchContextBuilder,
        )

        let metadataBySessionID: [TerminalSessionID: (title: String, directory: String, transcript: String)] = [
            leftPane.sessionID: ("Left Shell", "/tmp/layout/left", "printf left\n"),
            rightPane.sessionID: ("Right Shell", "/tmp/layout/right", "printf right\n"),
        ]

        for leaf in workspace.paneLeaves {
            let session = model.sessions.ensureSession(id: leaf.sessionID)
            let metadata = try #require(metadataBySessionID[leaf.sessionID])
            session.title = metadata.title
            session.currentDirectory = metadata.directory
        }

        let summary = try #require(
            model.saveWorkspaceToLibrary(
                workspace.id,
                transcriptsBySessionID: Dictionary(
                    uniqueKeysWithValues: metadataBySessionID.map { ($0.key, $0.value.transcript) },
                ),
            ),
        )
        let context = persistence.container.viewContext

        let missingSessionEntity = try #require(try fetchPaneSessionPayloadEntity(id: rightPane.sessionID, in: context))
        context.delete(missingSessionEntity)
        try context.save()

        model.deleteWorkspace(workspace.id)
        let reopenedWorkspaceID = try #require(model.openSavedWorkspace(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedLeaves = reopenedWorkspace.paneLeaves
        #expect(reopenedLeaves.count == 2)
        #expect(reopenedWorkspaceID == workspace.id)

        let unaffectedSession = try #require(model.sessions.session(for: reopenedLeaves[0].sessionID))
        #expect(unaffectedSession.title == "Left Shell")
        #expect(unaffectedSession.currentDirectory == "/tmp/layout/left")
        #expect(unaffectedSession.consumeRestoredTranscript() == "printf left\n")

        let fallbackSession = try #require(model.sessions.session(for: reopenedLeaves[1].sessionID))
        #expect(fallbackSession.title == "Shell")
        #expect(fallbackSession.currentDirectory == "/tmp/default-fallback")
        #expect(fallbackSession.consumeRestoredTranscript() == nil)
    }

    @Test func `close workspace to library creates A reusable saved workspace and selects the neighbor`() throws {
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
        let nextSelectedWorkspaceID = model.closeWorkspaceToLibrary(
            firstWorkspace.id,
            transcriptsBySessionID: [firstPane.sessionID: "echo library-close\n"],
        )

        let savedWorkspace = try #require(model.listSavedWorkspaces().first)
        let reopenedWorkspaceID = try #require(model.openSavedWorkspace(savedWorkspace.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))

        #expect(nextSelectedWorkspaceID == secondWorkspace.id)
        #expect(model.workspaces.count == 2)
        #expect(reopenedWorkspaceID == firstWorkspace.id)
        #expect(reopenedWorkspace.title == "Workspace 1")
    }

    @Test func `load workspaces discards persisted workspace when its pane tree is corrupted`() throws {
        let leftPane = PaneLeaf()
        let rightPane = PaneLeaf()
        let workspace = Workspace(
            title: "Workspace 1",
            root: .split(
                PaneSplit(
                    axis: .horizontal,
                    fraction: 0.5,
                    first: .leaf(leftPane),
                    second: .leaf(rightPane),
                ),
            ),
        )
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        persistence.saveSceneState(
            for: sceneIdentity,
            liveWorkspaces: [workspace],
            selectedWorkspaceID: workspace.id,
            sessions: TerminalSessionRegistry(
                workspaces: [workspace],
                defaultLaunchConfiguration: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests").makeLaunchConfiguration(),
            ),
        )
        let context = persistence.container.viewContext

        let workspaceEntity = try #require(try fetchWorkspaceEntity(id: workspace.id, in: context))
        let rootNode = try #require(workspaceEntity.rootNode)
        rootNode.axis = nil
        try context.save()

        let restoredWorkspaces = persistence.loadWorkspaces(for: sceneIdentity)

        #expect(restoredWorkspaces.isEmpty)
    }

    @Test func `scene identities restore independent live workspace sets`() {
        let firstSceneIdentity = WorkspaceSceneIdentity()
        let secondSceneIdentity = WorkspaceSceneIdentity()
        let firstSceneWorkspace = TestSupport.makeWorkspace(title: "Window A")
        let secondSceneWorkspace = TestSupport.makeWorkspace(title: "Window B")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let launchConfiguration = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests").makeLaunchConfiguration()

        persistence.saveSceneState(
            for: firstSceneIdentity,
            liveWorkspaces: [firstSceneWorkspace],
            selectedWorkspaceID: firstSceneWorkspace.id,
            sessions: TerminalSessionRegistry(
                workspaces: [firstSceneWorkspace],
                defaultLaunchConfiguration: launchConfiguration,
            ),
        )
        persistence.saveSceneState(
            for: secondSceneIdentity,
            liveWorkspaces: [secondSceneWorkspace],
            selectedWorkspaceID: secondSceneWorkspace.id,
            sessions: TerminalSessionRegistry(
                workspaces: [secondSceneWorkspace],
                defaultLaunchConfiguration: launchConfiguration,
            ),
        )

        let restoredFirstSceneWorkspaces = persistence.loadWorkspaces(for: firstSceneIdentity)
        let restoredSecondSceneWorkspaces = persistence.loadWorkspaces(for: secondSceneIdentity)

        #expect(restoredFirstSceneWorkspaces.map(\.title) == ["Window A"])
        #expect(restoredSecondSceneWorkspaces.map(\.title) == ["Window B"])
        #expect(restoredFirstSceneWorkspaces.first?.id == firstSceneWorkspace.id)
        #expect(restoredSecondSceneWorkspaces.first?.id == secondSceneWorkspace.id)
    }

    @Test func `scene identities restore independent recently closed workspaces`() {
        let firstSceneIdentity = WorkspaceSceneIdentity()
        let secondSceneIdentity = WorkspaceSceneIdentity()
        let firstRecentWorkspace = TestSupport.makeWorkspace(title: "Closed in Window A")
        let secondRecentWorkspace = TestSupport.makeWorkspace(title: "Closed in Window B")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let launchConfiguration = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests").makeLaunchConfiguration()

        persistence.recordRecentlyClosedWorkspace(
            RecentlyClosedWorkspaceStateInput(
                workspace: firstRecentWorkspace,
                formerIndex: 2,
                launchConfigurationsBySessionID: [:],
                titlesBySessionID: [:],
                transcriptsBySessionID: [:],
            ),
            for: firstSceneIdentity,
            limit: WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount,
        )
        persistence.recordRecentlyClosedWorkspace(
            RecentlyClosedWorkspaceStateInput(
                workspace: secondRecentWorkspace,
                formerIndex: 5,
                launchConfigurationsBySessionID: [:],
                titlesBySessionID: [:],
                transcriptsBySessionID: [:],
            ),
            for: secondSceneIdentity,
            limit: WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount,
        )

        let restoredFirstSceneRecentWorkspaces = persistence.loadRecentlyClosedWorkspaces(for: firstSceneIdentity)
        let restoredSecondSceneRecentWorkspaces = persistence.loadRecentlyClosedWorkspaces(for: secondSceneIdentity)

        #expect(restoredFirstSceneRecentWorkspaces.map(\.revision.title) == ["Closed in Window A"])
        #expect(restoredSecondSceneRecentWorkspaces.map(\.revision.title) == ["Closed in Window B"])
        #expect(restoredFirstSceneRecentWorkspaces.first?.formerIndex == 2)
        #expect(restoredSecondSceneRecentWorkspaces.first?.formerIndex == 5)
    }
}

private indirect enum PaneNodeSignature: Equatable {
    case leaf
    case split(axis: PaneSplit.Axis, fraction: Double, first: PaneNodeSignature, second: PaneNodeSignature)
}

@MainActor
private func nodeSignature(from node: PaneNode) -> PaneNodeSignature {
    switch node {
        case .leaf:
            .leaf
        case let .split(split):
            .split(
                axis: split.axis,
                fraction: Double(split.fraction),
                first: nodeSignature(from: split.first),
                second: nodeSignature(from: split.second),
            )
    }
}

@MainActor
private func fetchSavedWorkspacePlacement(
    id: WorkspaceID,
    in context: NSManagedObjectContext,
) throws -> WorkspacePlacementEntity? {
    let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
    request.fetchLimit = 1
    request.predicate = NSCompoundPredicate(
        andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id.rawValue as CVarArg),
            NSPredicate(format: "role == %@", WorkspacePlacementRole.library.rawValue),
        ],
    )
    return try context.fetch(request).first
}

@MainActor
private func fetchPaneSessionPayloadEntity(
    id: TerminalSessionID,
    in context: NSManagedObjectContext,
) throws -> PaneSessionSnapshotEntity? {
    let request = NSFetchRequest<PaneSessionSnapshotEntity>(entityName: "PaneSessionSnapshotEntity")
    request.fetchLimit = 1
    request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
    return try context.fetch(request).first
}

@MainActor
private func fetchWorkspaceEntity(
    id: WorkspaceID,
    in context: NSManagedObjectContext,
) throws -> WorkspaceEntity? {
    let request = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
    request.fetchLimit = 1
    request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
    return try context.fetch(request).first
}
