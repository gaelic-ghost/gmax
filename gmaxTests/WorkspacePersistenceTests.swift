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

    @Test func `persistSceneStateNow writes the durable selected pane for a window`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let pane = PaneLeaf()
        let workspace = Workspace(title: "Workspace 1", root: .leaf(pane))
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [workspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.persistedSelectedWorkspaceID = workspace.id
        model.persistedSelectedPaneID = pane.id
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)

        let restoredWindowState = try #require(persistence.loadWindowState(for: sceneIdentity))
        #expect(restoredWindowState.selectedWorkspaceID == workspace.id)
        #expect(restoredWindowState.selectedPaneID == pane.id)
    }

    @Test func `load window state migrates legacy selected pane onto durable window record`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let context = persistence.container.viewContext
        let sceneIdentity = WorkspaceSceneIdentity()
        let workspaceID = WorkspaceID()
        let paneID = PaneID()

        try context.performAndWait {
            let legacyState = WorkspaceWindowStateEntity(context: context)
            legacyState.windowID = sceneIdentity.windowID
            legacyState.selectedWorkspaceID = workspaceID.rawValue
            legacyState.selectedPaneID = paneID.rawValue
            legacyState.createdAt = Date()
            legacyState.updatedAt = Date()

            try context.save()
        }

        let restoredWindowState = try #require(persistence.loadWindowState(for: sceneIdentity))
        #expect(restoredWindowState.selectedWorkspaceID == workspaceID)
        #expect(restoredWindowState.selectedPaneID == paneID)
    }

    @Test func `persistSceneStateNow creates an open durable window record`() {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [workspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.persistedSelectedWorkspaceID = workspace.id
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)

        #expect(persistence.loadLiveSceneIdentities() == [sceneIdentity])
    }

    @Test func `markWindowClosed moves a persisted window into recently closed history`() {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [workspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.persistedSelectedWorkspaceID = workspace.id
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)
        persistence.markWindowClosed(sceneIdentity, saveToLibrary: true)

        #expect(persistence.loadLiveSceneIdentities().isEmpty)
        #expect(persistence.loadRecentlyClosedWindowSceneIdentities() == [sceneIdentity])
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
        #expect(summary.workspaceID == workspace.id)

        let reopenedWorkspaceID = try requireWorkspaceOpenResult(model.openLibraryItem(summary.id))
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
            #expect(restoredSession.consumeRestoredHistory()?.transcript == metadata.transcript)
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
        #expect(summary.workspaceID == workspace.id)

        let reopenedWorkspaceID = try requireWorkspaceOpenResult(model.openLibraryItem(summary.id))
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
            #expect(restoredSession.consumeRestoredHistory()?.transcript == metadata.transcript)
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
        #expect(summary.workspaceID == workspace.id)

        let reopenedWorkspaceID = try requireWorkspaceOpenResult(model.openLibraryItem(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedPane = try #require(reopenedWorkspace.root?.firstLeaf())
        let reopenedSession = try #require(model.sessions.session(for: reopenedPane.sessionID))

        #expect(visibleWorkspaceLibraryItems(in: model).isEmpty)
        #expect(reopenedWorkspaceID == workspace.id)
        #expect(reopenedWorkspace.title.starts(with: "Workspace 1"))
        #expect(reopenedSession.title == "Build Shell")
        #expect(reopenedSession.currentDirectory == "/tmp/workspace-library")
        #expect(reopenedSession.consumeRestoredHistory()?.transcript == "$ pwd\n/tmp/workspace-library\n")
    }

    @Test func `workspace library persistence round-trips restored history metadata`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let launchConfiguration = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
            .makeLaunchConfiguration()
        let sessions = TerminalSessionRegistry(
            workspaces: [workspace],
            defaultLaunchConfiguration: launchConfiguration,
        )
        let browserSessions = BrowserSessionRegistry(workspaces: [workspace])
        let pane = try #require(workspace.root?.firstLeaf())
        let session = sessions.ensureSession(id: pane.sessionID)
        session.title = "History Shell"
        session.currentDirectory = "/tmp/history-restore"

        let history = WorkspaceSessionHistorySnapshot(
            transcript: "$ pwd\n/tmp/history-restore\n",
            normalScrollPosition: 0.68,
            wasAlternateBufferActive: true,
        )
        let summary = try #require(
            persistence.saveWorkspaceToLibrary(
                from: workspace,
                sessions: sessions,
                browserSessions: browserSessions,
                historyBySessionID: [pane.sessionID: history],
            ),
        )
        let restoredRevision = try #require(persistence.loadWorkspaceLibraryItem(id: summary.id))
        let restoredPaneSnapshot = try #require(restoredRevision.paneSnapshotsBySessionID[pane.sessionID])

        #expect(restoredPaneSnapshot.title == "History Shell")
        #expect(restoredPaneSnapshot.launchConfiguration.currentDirectory == "/tmp/history-restore")
        #expect(restoredPaneSnapshot.history == history)
        #expect(restoredPaneSnapshot.transcriptByteCount == (history.transcript?.utf8.count ?? 0))
        #expect(restoredPaneSnapshot.transcriptLineCount == 3)
    }

    @Test func `live window restore seeds terminal sessions from persisted pane snapshots`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let pane = try #require(workspace.root?.firstLeaf())
        let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
        let launchConfiguration = TerminalLaunchConfiguration(
            executable: "/bin/zsh",
            arguments: ["-l"],
            environment: nil,
            currentDirectory: "/tmp/live-restore",
        )
        let sessions = TerminalSessionRegistry(
            workspaces: [workspace],
            defaultLaunchConfiguration: launchContextBuilder.makeLaunchConfiguration(),
        )
        let session = sessions.ensureSession(id: pane.sessionID, launchConfiguration: launchConfiguration)
        session.title = "Live Restore Shell"
        session.currentDirectory = "/tmp/live-restore"

        persistence.saveSceneState(
            for: sceneIdentity,
            liveWorkspaces: [workspace],
            selectedWorkspaceID: workspace.id,
            selectedPaneID: nil,
            sessions: sessions,
            browserSessions: BrowserSessionRegistry(workspaces: [workspace]),
            liveHistoryByWorkspaceID: [
                workspace.id: [
                    pane.sessionID: WorkspaceSessionHistorySnapshot(
                        transcript: "$ pwd\n/tmp/live-restore\n",
                        normalScrollPosition: 0.42,
                        wasAlternateBufferActive: false,
                    ),
                ],
            ],
        )

        let restoredStore = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            persistence: persistence,
            launchContextBuilder: launchContextBuilder,
        )
        let restoredWorkspace = try #require(restoredStore.workspaces.first)
        let restoredPane = try #require(restoredWorkspace.root?.firstLeaf())
        let restoredSession = try #require(restoredStore.sessions.session(for: restoredPane.sessionID))
        let restoredHistory = try #require(restoredSession.consumeRestoredHistory())

        #expect(restoredSession.title == "Live Restore Shell")
        #expect(restoredSession.currentDirectory == "/tmp/live-restore")
        #expect(restoredSession.launchConfiguration.currentDirectory == "/tmp/live-restore")
        #expect(restoredHistory.transcript == "$ pwd\n/tmp/live-restore\n")
        #expect(restoredHistory.normalScrollPosition == 0.42)
        #expect(restoredHistory.wasAlternateBufferActive == false)
    }

    @Test func `live window restore seeds browser sessions from persisted browser snapshots`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let browserPane = PaneLeaf(content: .browser(BrowserSessionID()))
        let workspace = Workspace(
            title: "Workspace 1",
            root: .leaf(browserPane),
        )
        let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")
        let sessions = TerminalSessionRegistry(
            workspaces: [workspace],
            defaultLaunchConfiguration: launchContextBuilder.makeLaunchConfiguration(),
        )
        let browserSessions = BrowserSessionRegistry(workspaces: [workspace])
        let browserSessionID = try #require(browserPane.browserSessionID)
        let browserSession = try #require(browserSessions.session(for: browserSessionID))
        browserSession.title = "WebKit Docs"
        browserSession.url = "https://developer.apple.com/documentation/webkit/wkwebview"
        browserSession.lastCommittedURL = browserSession.url
        browserSession.state = .failed("Browser navigation failed: offline")
        browserSession.history = BrowserSessionHistorySnapshot(
            items: [
                BrowserHistoryItemSnapshot(
                    url: "https://developer.apple.com/documentation",
                    title: "Documentation",
                ),
                BrowserHistoryItemSnapshot(
                    url: "https://developer.apple.com/documentation/webkit/wkwebview",
                    title: "WKWebView",
                ),
                BrowserHistoryItemSnapshot(
                    url: "https://developer.apple.com/documentation/webkit/wkbackforwardlist",
                    title: "WKBackForwardList",
                ),
            ],
            currentIndex: 1,
        )

        persistence.saveSceneState(
            for: sceneIdentity,
            liveWorkspaces: [workspace],
            selectedWorkspaceID: workspace.id,
            selectedPaneID: nil,
            sessions: sessions,
            browserSessions: browserSessions,
            liveHistoryByWorkspaceID: [:],
            liveBrowserSnapshotsByWorkspaceID: [
                workspace.id: [
                    browserSessionID: browserSession.makeSnapshot(),
                ],
            ],
        )

        let restoredStore = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            persistence: persistence,
            launchContextBuilder: launchContextBuilder,
        )
        let restoredWorkspace = try #require(restoredStore.workspaces.first)
        let restoredPane = try #require(restoredWorkspace.root?.firstLeaf())
        let restoredBrowserSessionID = try #require(restoredPane.browserSessionID)
        let restoredBrowserSession = try #require(restoredStore.browserSessions.session(for: restoredBrowserSessionID))

        #expect(restoredBrowserSession.title == "WebKit Docs")
        #expect(restoredBrowserSession.url == "https://developer.apple.com/documentation/webkit/wkwebview")
        #expect(restoredBrowserSession.lastCommittedURL == "https://developer.apple.com/documentation/webkit/wkwebview")
        #expect(restoredBrowserSession.state == .failed("Browser navigation failed: offline"))
        #expect(restoredBrowserSession.history == browserSession.history)
        #expect(restoredBrowserSession.canGoBack)
        #expect(restoredBrowserSession.canGoForward)
    }

    @Test func `save and open saved workspace restore browser history snapshots`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let browserPane = PaneLeaf(content: .browser(BrowserSessionID()))
        let workspace = Workspace(
            title: "Workspace 1",
            root: .leaf(browserPane),
        )
        let siblingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            workspaces: [workspace, siblingWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let browserSessionID = try #require(browserPane.browserSessionID)
        let browserSession = try #require(model.browserSessions.session(for: browserSessionID))
        browserSession.title = "WebKit"
        browserSession.url = "https://developer.apple.com/documentation/webkit/wkbackforwardlist"
        browserSession.lastCommittedURL = browserSession.url
        browserSession.history = BrowserSessionHistorySnapshot(
            items: [
                BrowserHistoryItemSnapshot(
                    url: "https://developer.apple.com/documentation/webkit/wkwebview",
                    title: "WKWebView",
                ),
                BrowserHistoryItemSnapshot(
                    url: "https://developer.apple.com/documentation/webkit/wkbackforwardlist",
                    title: "WKBackForwardList",
                ),
            ],
            currentIndex: 1,
        )

        let summary = try #require(model.saveWorkspaceToLibrary(workspace.id))
        model.deleteWorkspace(workspace.id)
        let reopenedWorkspaceID = try requireWorkspaceOpenResult(model.openLibraryItem(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedBrowserPane = try #require(reopenedWorkspace.root?.firstLeaf())
        let reopenedBrowserSessionID = try #require(reopenedBrowserPane.browserSessionID)
        let reopenedBrowserSession = try #require(model.browserSessions.session(for: reopenedBrowserSessionID))

        #expect(reopenedBrowserSession.title == "WebKit")
        #expect(reopenedBrowserSession.url == "https://developer.apple.com/documentation/webkit/wkbackforwardlist")
        #expect(reopenedBrowserSession.lastCommittedURL == "https://developer.apple.com/documentation/webkit/wkbackforwardlist")
        #expect(reopenedBrowserSession.history == browserSession.history)
        #expect(reopenedBrowserSession.canGoBack)
        #expect(!reopenedBrowserSession.canGoForward)
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

        #expect(summary.workspaceID == workspace.id)

        let reopenedWorkspaceID = try requireWorkspaceOpenResult(model.openLibraryItem(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedRoot = try #require(reopenedWorkspace.root)

        #expect(reopenedWorkspaceID == workspace.id)
        #expect(model.workspaces.count == 1)
        #expect(visibleWorkspaceLibraryItems(in: model).isEmpty)
        #expect(nodeSignature(from: reopenedRoot) == expectedSignature)
    }

    @Test func `deleting a saved workspace removes it from the library listing`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let siblingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let model = WorkspaceStore(
            workspaces: [workspace, siblingWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        let savedWorkspace = try #require(model.saveWorkspaceToLibrary(workspace.id))
        #expect(visibleWorkspaceLibraryItems(in: model).isEmpty)
        #expect(savedWorkspace.workspaceID == workspace.id)
        #expect(persistence.listLibraryItems().map(\.id) == [savedWorkspace.id])
        #expect(persistence.listLibraryItems().compactMap(\.workspaceID) == [workspace.id])

        model.deleteLibraryItem(savedWorkspace.id)

        #expect(visibleWorkspaceLibraryItems(in: model).isEmpty)
        #expect(persistence.listLibraryItems().isEmpty)
    }

    @Test func `closing a window adds a saved window item to the library listing`() {
        let firstWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let secondWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [firstWorkspace, secondWorkspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.persistedSelectedWorkspaceID = secondWorkspace.id
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)
        persistence.markWindowClosed(sceneIdentity, saveToLibrary: true)

        let windowItems = persistence.listLibraryItems().filter { $0.kind == .window }

        #expect(windowItems.count == 1)
        #expect(windowItems.first?.windowID == sceneIdentity)
        #expect(windowItems.first?.workspaceID == nil)
        #expect(windowItems.first?.title == "Workspace 2")
        #expect(windowItems.first?.workspaceCount == 2)
        #expect(windowItems.first?.paneCount == 2)
    }

    @Test func `opening a saved window library item returns the same durable scene identity`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [workspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.persistedSelectedWorkspaceID = workspace.id
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)
        persistence.markWindowClosed(sceneIdentity, saveToLibrary: true)

        let libraryItemID = try #require(
            persistence.listLibraryItems().first(where: { $0.kind == .window })?.id,
        )

        let openResult = model.openLibraryItem(libraryItemID)

        #expect(openResult == .window(sceneIdentity))
    }

    @Test func `closing a window without library auto-save does not add a saved window item`() {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sceneIdentity = WorkspaceSceneIdentity()
        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [workspace],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        model.persistedSelectedWorkspaceID = workspace.id
        model.persistSceneStateNow(reason: .unitTestImmediateFlush)
        persistence.markWindowClosed(sceneIdentity, saveToLibrary: false)

        #expect(persistence.loadRecentlyClosedWindowSceneIdentities() == [sceneIdentity])
        #expect(persistence.listLibraryItems().contains(where: { $0.kind == .window }) == false)
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

        let savedWorkspaceLibraryItem = try #require(try fetchWorkspaceLibraryItem(workspaceID: workspace.id.rawValue, in: context))
        let savedWorkspaceID = try #require(savedWorkspaceLibraryItem.workspaceID)
        let workspaceEntity = try #require(try fetchWorkspaceEntity(id: savedWorkspaceID, in: context))
        let rootNode = try #require(workspaceEntity.rootNode)
        rootNode.firstChild = nil
        try context.save()

        model.deleteWorkspace(workspace.id)
        #expect(summary.workspaceID == workspace.id)

        let reopenedWorkspaceID = workspaceOpenResult(model.openLibraryItem(summary.id))

        #expect(reopenedWorkspaceID == nil)
        #expect(model.workspaces.count == 1)
        #expect(visibleWorkspaceLibraryItems(in: model).count == 1)
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

        let missingSessionEntity = try #require(try fetchPaneSessionPayloadEntity(id: rightPane.sessionID.rawValue, in: context))
        context.delete(missingSessionEntity)
        try context.save()

        model.deleteWorkspace(workspace.id)
        #expect(summary.workspaceID == workspace.id)

        let reopenedWorkspaceID = try requireWorkspaceOpenResult(model.openLibraryItem(summary.id))
        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == reopenedWorkspaceID }))
        let reopenedLeaves = reopenedWorkspace.paneLeaves
        #expect(reopenedLeaves.count == 2)
        #expect(reopenedWorkspaceID == workspace.id)

        let unaffectedSession = try #require(model.sessions.session(for: reopenedLeaves[0].sessionID))
        #expect(unaffectedSession.title == "Left Shell")
        #expect(unaffectedSession.currentDirectory == "/tmp/layout/left")
        #expect(unaffectedSession.consumeRestoredHistory()?.transcript == "printf left\n")

        let fallbackSession = try #require(model.sessions.session(for: reopenedLeaves[1].sessionID))
        #expect(fallbackSession.title == "Shell")
        #expect(fallbackSession.currentDirectory == "/tmp/default-fallback")
        #expect(fallbackSession.consumeRestoredHistory()?.transcript == nil)
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

        let savedWorkspace = try #require(visibleWorkspaceLibraryItems(in: model).first)
        let reopenedWorkspaceID = try requireWorkspaceOpenResult(model.openLibraryItem(savedWorkspace.id))
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
            selectedPaneID: nil,
            sessions: TerminalSessionRegistry(
                workspaces: [workspace],
                defaultLaunchConfiguration: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests").makeLaunchConfiguration(),
            ),
            browserSessions: BrowserSessionRegistry(workspaces: [workspace]),
        )
        let context = persistence.container.viewContext

        let workspaceEntity = try #require(try fetchWorkspaceEntity(id: workspace.id.rawValue, in: context))
        let rootNode = try #require(workspaceEntity.rootNode)
        rootNode.axis = nil
        try context.save()

        let restoredWorkspaces = persistence.loadWorkspaces(for: sceneIdentity)

        #expect(restoredWorkspaces.isEmpty)
    }

    @Test func `pane node coding round trips terminal browser and legacy leaf content`() throws {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let context = persistence.container.viewContext
        let terminalPane = PaneLeaf(content: .terminal(TerminalSessionID()))
        let browserPane = PaneLeaf(content: .browser(BrowserSessionID()))
        let split = PaneSplit(
            axis: .vertical,
            fraction: 0.35,
            first: .leaf(terminalPane),
            second: .leaf(browserPane),
        )

        let encodedRoot = try #require(
            WorkspacePersistenceController.makeNodeEntity(from: .split(split), context: context),
        )
        let decodedRoot = try #require(WorkspacePersistenceController.decodeNode(encodedRoot))
        let decodedSplit = try #require(extractRootSplit(from: decodedRoot))
        let decodedTerminalPane = try #require(extractRootLeaf(from: decodedSplit.first))
        let decodedBrowserPane = try #require(extractRootLeaf(from: decodedSplit.second))

        #expect(decodedSplit.axis == .vertical)
        #expect(decodedSplit.fraction == 0.35)
        #expect(decodedTerminalPane.terminalSessionID == terminalPane.terminalSessionID)
        #expect(decodedBrowserPane.browserSessionID == browserPane.browserSessionID)

        let legacyTerminalNode = PaneNodeEntity(context: context)
        legacyTerminalNode.id = UUID()
        legacyTerminalNode.kind = PaneNodeKind.leaf.rawValue
        legacyTerminalNode.contentKind = nil
        legacyTerminalNode.sessionID = UUID()
        legacyTerminalNode.browserSessionID = nil

        let decodedLegacyNode = try #require(WorkspacePersistenceController.decodeNode(legacyTerminalNode))
        #expect(extractRootLeaf(from: decodedLegacyNode)?.terminalSessionID?.rawValue == legacyTerminalNode.sessionID)
    }

    @Test func `pane node decoding skips malformed leaf split and unknown kind payloads`() {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let context = persistence.container.viewContext

        let missingTerminalSession = PaneNodeEntity(context: context)
        missingTerminalSession.id = UUID()
        missingTerminalSession.kind = PaneNodeKind.leaf.rawValue
        missingTerminalSession.contentKind = PersistedPaneContentKind.terminal.rawValue
        missingTerminalSession.sessionID = nil

        let missingBrowserSession = PaneNodeEntity(context: context)
        missingBrowserSession.id = UUID()
        missingBrowserSession.kind = PaneNodeKind.leaf.rawValue
        missingBrowserSession.contentKind = PersistedPaneContentKind.browser.rawValue
        missingBrowserSession.browserSessionID = nil

        let invalidSplit = PaneNodeEntity(context: context)
        invalidSplit.id = UUID()
        invalidSplit.kind = PaneNodeKind.split.rawValue
        invalidSplit.axis = nil

        let unknownKind = PaneNodeEntity(context: context)
        unknownKind.id = UUID()
        unknownKind.kind = "definitely-not-a-pane-node-kind"

        #expect(WorkspacePersistenceController.decodeNode(missingTerminalSession) == nil)
        #expect(WorkspacePersistenceController.decodeNode(missingBrowserSession) == nil)
        #expect(WorkspacePersistenceController.decodeNode(invalidSplit) == nil)
        #expect(WorkspacePersistenceController.decodeNode(unknownKind) == nil)
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
            selectedPaneID: nil,
            sessions: TerminalSessionRegistry(
                workspaces: [firstSceneWorkspace],
                defaultLaunchConfiguration: launchConfiguration,
            ),
            browserSessions: BrowserSessionRegistry(workspaces: [firstSceneWorkspace]),
        )
        persistence.saveSceneState(
            for: secondSceneIdentity,
            liveWorkspaces: [secondSceneWorkspace],
            selectedWorkspaceID: secondSceneWorkspace.id,
            selectedPaneID: nil,
            sessions: TerminalSessionRegistry(
                workspaces: [secondSceneWorkspace],
                defaultLaunchConfiguration: launchConfiguration,
            ),
            browserSessions: BrowserSessionRegistry(workspaces: [secondSceneWorkspace]),
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
        persistence.recordWorkspaceInRecentHistory(
            WindowWorkspaceHistoryInput(
                workspace: firstRecentWorkspace,
                formerIndex: 2,
                launchConfigurationsBySessionID: [:],
                titlesBySessionID: [:],
                historyBySessionID: [:],
                browserSnapshotsBySessionID: [:],
            ),
            for: firstSceneIdentity,
            limit: WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount,
        )
        persistence.recordWorkspaceInRecentHistory(
            WindowWorkspaceHistoryInput(
                workspace: secondRecentWorkspace,
                formerIndex: 5,
                launchConfigurationsBySessionID: [:],
                titlesBySessionID: [:],
                historyBySessionID: [:],
                browserSnapshotsBySessionID: [:],
            ),
            for: secondSceneIdentity,
            limit: WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount,
        )

        let restoredFirstSceneRecentWorkspaces = persistence.loadRecentWorkspaceHistory(for: firstSceneIdentity)
        let restoredSecondSceneRecentWorkspaces = persistence.loadRecentWorkspaceHistory(for: secondSceneIdentity)

        #expect(restoredFirstSceneRecentWorkspaces.map(\.revision.title) == ["Closed in Window A"])
        #expect(restoredSecondSceneRecentWorkspaces.map(\.revision.title) == ["Closed in Window B"])
        #expect(restoredFirstSceneRecentWorkspaces.first?.formerIndex == 2)
        #expect(restoredSecondSceneRecentWorkspaces.first?.formerIndex == 5)
    }

    @MainActor
    @Test func `recording window recent workspace stores membership history instead of creating a recent placement`() throws {
        let sceneIdentity = WorkspaceSceneIdentity()
        let recentWorkspace = TestSupport.makeWorkspace(title: "Closed Workspace")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()

        persistence.recordWorkspaceInRecentHistory(
            WindowWorkspaceHistoryInput(
                workspace: recentWorkspace,
                formerIndex: 3,
                launchConfigurationsBySessionID: [:],
                titlesBySessionID: [:],
                historyBySessionID: [:],
                browserSnapshotsBySessionID: [:],
            ),
            for: sceneIdentity,
            limit: WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount,
        )

        let context = persistence.container.viewContext
        let workspaceID = recentWorkspace.id.rawValue
        let windowID = sceneIdentity.windowID
        let fetchedWorkspaceEntity = try fetchWorkspaceEntity(id: workspaceID, in: context)
        let workspaceEntity = try #require(fetchedWorkspaceEntity)
        let recentMemberships = try fetchWindowWorkspaceMemberships(windowID: windowID, in: context)
        let recentPlacements = try fetchWindowRecentPlacements(windowID: windowID, in: context)

        #expect(workspaceEntity.recentWindowID == nil)
        #expect(workspaceEntity.recentSortOrder == 0)
        #expect(recentMemberships.map(\.workspaceID) == [workspaceID])
        #expect(recentMemberships.first?.sortOrder == 3)
        #expect(recentPlacements.isEmpty)
    }

    @MainActor
    @Test func `loading window recent workspaces migrates legacy recent placements onto workspace memberships`() throws {
        let sceneIdentity = WorkspaceSceneIdentity()
        let recentWorkspace = TestSupport.makeWorkspace(title: "Legacy Closed Workspace")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let sessions = TerminalSessionRegistry(
            workspaces: [recentWorkspace],
            defaultLaunchConfiguration: .loginShell,
        )
        let context = persistence.container.viewContext
        let workspaceID = recentWorkspace.id.rawValue
        let workspaceTitle = recentWorkspace.title
        let workspacePaneCount = Int64(recentWorkspace.root?.leaves().count ?? 0)
        let windowID = sceneIdentity.windowID

        persistence.saveSceneState(
            for: sceneIdentity,
            liveWorkspaces: [recentWorkspace],
            selectedWorkspaceID: recentWorkspace.id,
            selectedPaneID: nil,
            sessions: sessions,
            browserSessions: BrowserSessionRegistry(workspaces: [recentWorkspace]),
        )

        try context.performAndWait {
            let fetchedWorkspaceEntity = try fetchWorkspaceEntity(id: workspaceID, in: context)
            let workspaceEntity = try #require(fetchedWorkspaceEntity)
            let fetchedLivePlacement = try fetchLiveWorkspacePlacement(id: workspaceID, windowID: windowID, in: context)
            let livePlacement = try #require(fetchedLivePlacement)
            context.delete(livePlacement)

            let placement = WorkspacePlacementEntity(context: context)
            placement.id = workspaceID
            placement.role = WorkspacePersistenceLegacy.recentPlacementRoleRawValue
            placement.windowID = windowID
            placement.sortOrder = 0
            placement.restoreSortOrder = 4
            placement.createdAt = Date()
            placement.updatedAt = Date()
            placement.lastOpenedAt = nil
            placement.isPinned = false
            placement.title = workspaceTitle
            placement.previewText = nil
            placement.searchText = nil
            placement.paneCount = workspacePaneCount
            placement.workspace = workspaceEntity

            try context.save()
        }

        let restoredRecentWorkspaces = persistence.loadRecentWorkspaceHistory(for: sceneIdentity)
        let fetchedMigratedWorkspaceEntity = try fetchWorkspaceEntity(id: workspaceID, in: context)
        let migratedWorkspaceEntity = try #require(fetchedMigratedWorkspaceEntity)
        let recentMemberships = try fetchWindowWorkspaceMemberships(windowID: windowID, in: context)
        let remainingRecentPlacements = try fetchWindowRecentPlacements(windowID: windowID, in: context)

        #expect(restoredRecentWorkspaces.map(\.revision.title) == ["Legacy Closed Workspace"])
        #expect(restoredRecentWorkspaces.first?.formerIndex == 4)
        #expect(migratedWorkspaceEntity.recentWindowID == nil)
        #expect(migratedWorkspaceEntity.recentSortOrder == 0)
        #expect(recentMemberships.map(\.workspaceID) == [workspaceID])
        #expect(recentMemberships.first?.sortOrder == 4)
        #expect(remainingRecentPlacements.isEmpty)
    }

    @MainActor
    @Test func `listing saved workspaces migrates legacy library placements onto library items`() throws {
        let workspace = TestSupport.makeWorkspace(title: "Legacy Saved Workspace")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let context = persistence.container.viewContext
        let sessions = TerminalSessionRegistry(
            workspaces: [workspace],
            defaultLaunchConfiguration: .loginShell,
        )
        let sceneIdentity = WorkspaceSceneIdentity()

        persistence.saveSceneState(
            for: sceneIdentity,
            liveWorkspaces: [workspace],
            selectedWorkspaceID: workspace.id,
            selectedPaneID: nil,
            sessions: sessions,
            browserSessions: BrowserSessionRegistry(workspaces: [workspace]),
        )

        let workspaceID = workspace.id.rawValue
        let workspaceTitle = workspace.title
        let workspacePaneCount = workspace.paneCount
        let windowID = sceneIdentity.windowID

        try context.performAndWait {
            let workspaceEntity = try #require(try fetchWorkspaceEntity(id: workspaceID, in: context))
            let livePlacement = try #require(
                try fetchLiveWorkspacePlacement(id: workspaceID, windowID: windowID, in: context),
            )
            context.delete(livePlacement)

            let legacyPlacement = WorkspacePlacementEntity(context: context)
            legacyPlacement.id = workspaceID
            legacyPlacement.role = WorkspacePersistenceLegacy.libraryPlacementRoleRawValue
            legacyPlacement.windowID = nil
            legacyPlacement.sortOrder = 0
            legacyPlacement.restoreSortOrder = 0
            legacyPlacement.createdAt = Date()
            legacyPlacement.updatedAt = Date()
            legacyPlacement.lastOpenedAt = nil
            legacyPlacement.isPinned = true
            legacyPlacement.title = workspaceTitle
            legacyPlacement.previewText = "legacy preview"
            legacyPlacement.searchText = "legacy search"
            legacyPlacement.paneCount = Int64(workspacePaneCount)
            legacyPlacement.workspace = workspaceEntity

            try context.save()
        }

        let listings = persistence.listLibraryItems()
        let libraryItems = try fetchLibraryItems(in: context)
        let remainingLegacyPlacements = try fetchLegacyLibraryPlacements(in: context)

        #expect(listings.count == 1)
        #expect(listings.first?.kind == .workspace)
        #expect(listings.first?.workspaceID == workspace.id)
        #expect(listings.first?.isPinned == true)
        #expect(libraryItems.count == 1)
        #expect(libraryItems.first?.kind == LibraryItemKind.workspace.rawValue)
        #expect(libraryItems.first?.workspaceID == workspace.id.rawValue)
        #expect(remainingLegacyPlacements.isEmpty)
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

@MainActor
private func visibleWorkspaceLibraryItems(in model: WorkspaceStore) -> [LibraryItemListing] {
    let liveWorkspaceIDs = Set(model.workspaces.map(\.id))
    return model.listLibraryItems().filter { libraryItem in
        guard libraryItem.kind == .workspace, let workspaceID = libraryItem.workspaceID else {
            return false
        }

        return !liveWorkspaceIDs.contains(workspaceID)
    }
}

private func workspaceOpenResult(_ result: LibraryOpenResult?) -> WorkspaceID? {
    guard case let .workspace(workspaceID)? = result else {
        return nil
    }

    return workspaceID
}

private func requireWorkspaceOpenResult(
    _ result: LibraryOpenResult?,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws -> WorkspaceID {
    try #require(workspaceOpenResult(result), sourceLocation: sourceLocation)
}

private func fetchWorkspaceLibraryItem(
    workspaceID: UUID,
    in context: NSManagedObjectContext,
) throws -> LibraryItemEntity? {
    let request = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
    request.fetchLimit = 1
    request.predicate = NSCompoundPredicate(
        andPredicateWithSubpredicates: [
            NSPredicate(format: "kind == %@", LibraryItemKind.workspace.rawValue),
            NSPredicate(format: "workspaceID == %@", workspaceID as CVarArg),
        ],
    )
    return try context.fetch(request).first
}

private func fetchLibraryItems(
    in context: NSManagedObjectContext,
) throws -> [LibraryItemEntity] {
    let request = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
    request.sortDescriptors = [NSSortDescriptor(key: #keyPath(LibraryItemEntity.updatedAt), ascending: false)]
    return try context.fetch(request)
}

private func fetchPaneSessionPayloadEntity(
    id: UUID,
    in context: NSManagedObjectContext,
) throws -> PaneSessionSnapshotEntity? {
    let request = NSFetchRequest<PaneSessionSnapshotEntity>(entityName: "PaneSessionSnapshotEntity")
    request.fetchLimit = 1
    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
    return try context.fetch(request).first
}

private func fetchLiveWorkspacePlacement(
    id: UUID,
    windowID: UUID,
    in context: NSManagedObjectContext,
) throws -> WorkspacePlacementEntity? {
    let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
    request.fetchLimit = 1
    request.predicate = NSCompoundPredicate(
        andPredicateWithSubpredicates: [
            NSPredicate(format: "id == %@", id as CVarArg),
            NSPredicate(format: "role == %@", WorkspacePlacementRole.live.rawValue),
            NSPredicate(format: "windowID == %@", windowID as CVarArg),
        ],
    )
    return try context.fetch(request).first
}

private func fetchWorkspaceEntity(
    id: UUID,
    in context: NSManagedObjectContext,
) throws -> WorkspaceEntity? {
    let request = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
    request.fetchLimit = 1
    request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
    return try context.fetch(request).first
}

private func fetchWindowRecentPlacements(
    windowID: UUID,
    in context: NSManagedObjectContext,
) throws -> [WorkspacePlacementEntity] {
    let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
    request.predicate = NSCompoundPredicate(
        andPredicateWithSubpredicates: [
            NSPredicate(format: "role == %@", WorkspacePersistenceLegacy.recentPlacementRoleRawValue),
            NSPredicate(format: "windowID == %@", windowID as CVarArg),
        ],
    )
    return try context.fetch(request)
}

private func fetchLegacyLibraryPlacements(
    in context: NSManagedObjectContext,
) throws -> [WorkspacePlacementEntity] {
    let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
    request.predicate = NSPredicate(format: "role == %@", WorkspacePersistenceLegacy.libraryPlacementRoleRawValue)
    return try context.fetch(request)
}

private func fetchWindowWorkspaceMemberships(
    windowID: UUID,
    in context: NSManagedObjectContext,
) throws -> [WindowWorkspaceMembershipEntity] {
    let request = NSFetchRequest<WindowWorkspaceMembershipEntity>(entityName: "WindowWorkspaceMembershipEntity")
    request.predicate = NSPredicate(format: "windowID == %@", windowID as CVarArg)
    request.sortDescriptors = [NSSortDescriptor(key: #keyPath(WindowWorkspaceMembershipEntity.sortOrder), ascending: true)]
    return try context.fetch(request)
}
