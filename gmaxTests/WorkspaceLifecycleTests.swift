//
//  WorkspaceLifecycleTests.swift
//  gmaxTests
//
//  Created by Gale Williams on 4/14/26.
//

import CoreData
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
        let duplicatedSessions = Set(duplicatedWorkspace.paneLeaves.compactMap(\.terminalSessionID))

        #expect(duplicatedWorkspace.paneCount == workspace.paneCount)
        #expect(originalLeaves.isDisjoint(with: duplicatedLeaves))
        #expect(Set(workspace.paneLeaves.compactMap(\.terminalSessionID)).isDisjoint(with: duplicatedSessions))
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
        let firstSessionID = try #require(firstPane.terminalSessionID)
        let firstSession = model.sessions.ensureSession(id: firstSessionID)
        firstSession.currentDirectory = "/tmp/restored-workspace"

        _ = model.closeWorkspace(firstWorkspace.id)
        let reopenedWorkspaceID = model.undoCloseWorkspace()

        #expect(model.workspaces.count == 2)
        #expect(reopenedWorkspaceID == firstWorkspace.id)

        let reopenedWorkspace = try #require(model.workspaces.first(where: { $0.id == firstWorkspace.id }))
        let reopenedPane = try #require(reopenedWorkspace.root?.firstLeaf())
        let reopenedSessionID = try #require(reopenedPane.terminalSessionID)
        let reopenedSession = try #require(model.sessions.session(for: reopenedSessionID))
        #expect(reopenedSession.currentDirectory == "/tmp/restored-workspace")
    }

    @Test func `close workspace removes the last workspace without asking to close the window`() {
        let workspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let model = WorkspaceStore(workspaces: [workspace])

        let nextSelectedWorkspaceID = model.closeWorkspace(workspace.id)

        #expect(nextSelectedWorkspaceID == nil)
        #expect(model.workspaces.isEmpty)
    }

    @Test func `close workspace with recently closed disabled clears durable window history for that workspace`() throws {
        let defaults = UserDefaults.standard
        let defaultsKey = WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey
        let previousKeepRecentlyClosedValue = defaults.object(forKey: defaultsKey)
        defer {
            if let previousKeepRecentlyClosedValue {
                defaults.set(previousKeepRecentlyClosedValue, forKey: defaultsKey)
            } else {
                defaults.removeObject(forKey: defaultsKey)
            }
        }

        defaults.set(false, forKey: defaultsKey)

        let sceneIdentity = WorkspaceSceneIdentity()
        let closedWorkspace = TestSupport.makeWorkspace(title: "Workspace 1")
        let survivingWorkspace = TestSupport.makeWorkspace(title: "Workspace 2")
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let launchContextBuilder = TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests")

        persistence.recordWorkspaceInRecentHistory(
            WindowWorkspaceHistoryInput(
                workspace: closedWorkspace,
                formerIndex: 0,
                launchConfigurationsBySessionID: [:],
                titlesBySessionID: [:],
                historyBySessionID: [:],
                browserSnapshotsBySessionID: [:],
            ),
            for: sceneIdentity,
            limit: WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount,
        )

        let model = WorkspaceStore(
            sceneIdentity: sceneIdentity,
            workspaces: [closedWorkspace, survivingWorkspace],
            persistence: persistence,
            launchContextBuilder: launchContextBuilder,
        )

        let nextSelectedWorkspaceID = model.closeWorkspace(closedWorkspace.id)
        let remainingHistory = persistence.loadRecentWorkspaceHistory(for: sceneIdentity)
        let remainingMemberships = try fetchWindowWorkspaceMemberships(
            windowID: sceneIdentity.windowID,
            in: persistence.container.viewContext,
        )

        #expect(nextSelectedWorkspaceID == survivingWorkspace.id)
        #expect(model.recentlyClosedWorkspaceCount == 0)
        #expect(remainingHistory.isEmpty)
        #expect(remainingMemberships.isEmpty)
    }

    @Test func `default workspace store bootstrap does not require launching A shell process`() {
        let persistence = WorkspacePersistenceController.inMemoryForTesting()

        let model = WorkspaceStore(
            persistence: persistence,
        )

        #expect(model.workspaces.count == 1)
        #expect(model.workspaces[0].title == "Workspace 1")
    }

    @Test func `workspace store bootstraps browser sessions for browser leaves`() throws {
        let browserPane = PaneLeaf(content: .browser(BrowserSessionID()))
        let workspace = Workspace(
            title: "Workspace 1",
            root: .leaf(browserPane),
        )
        let model = WorkspaceStore(workspaces: [workspace])

        let browserSessionID = try #require(browserPane.browserSessionID)
        let session = try #require(model.browserSessions.session(for: browserSessionID))

        #expect(session.id == browserSessionID)
        #expect(session.title == "Browser")
        #expect(session.url == nil)
    }

    @Test func `browser navigation normalization prefers http for localhost and https for hostnames`() {
        #expect(
            BrowserNavigationDefaults.normalizedNavigationURLString(from: "localhost:3000")
                == "http://localhost:3000",
        )
        #expect(
            BrowserNavigationDefaults.normalizedNavigationURLString(from: "developer.apple.com/documentation/webkit/wkwebview")
                == "https://developer.apple.com/documentation/webkit/wkwebview",
        )
    }

    @Test func `browser navigation normalization trims values and rejects whitespace separated input`() {
        #expect(
            BrowserNavigationDefaults.normalizedNavigationURLString(from: "  127.0.0.1:8080  ")
                == "http://127.0.0.1:8080",
        )
        #expect(
            BrowserNavigationDefaults.normalizedNavigationURLString(from: "\n[::1]:5173\t")
                == "http://[::1]:5173",
        )
        #expect(BrowserNavigationDefaults.normalizedNavigationURLString(from: "") == nil)
        #expect(BrowserNavigationDefaults.normalizedNavigationURLString(from: "docs local") == nil)
    }

    @Test func `browser home URL normalization preserves supported explicit schemes`() {
        #expect(
            BrowserNavigationDefaults.normalizedNavigationURLString(from: "about:blank")
                == "about:blank",
        )
        #expect(
            BrowserNavigationDefaults.normalizedNavigationURLString(from: "file:///tmp/example.html")
                == "file:///tmp/example.html",
        )
    }

    @Test func `browser home URL defaults normalize configured values and fall back to blank page`() throws {
        let suiteName = "WorkspaceLifecycleTests.browser-home-defaults"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)

        #expect(BrowserNavigationDefaults.configuredHomePageURLString(userDefaults: userDefaults) == nil)
        #expect(BrowserNavigationDefaults.initialPageURLString(userDefaults: userDefaults) == "about:blank")

        userDefaults.set(" developer.apple.com/documentation/webkit ", forKey: BrowserNavigationDefaults.homePageURLKey)
        #expect(
            BrowserNavigationDefaults.configuredHomePageURLString(userDefaults: userDefaults)
                == "https://developer.apple.com/documentation/webkit",
        )
        #expect(
            BrowserNavigationDefaults.initialPageURLString(userDefaults: userDefaults)
                == "https://developer.apple.com/documentation/webkit",
        )

        userDefaults.set("not a valid URL", forKey: BrowserNavigationDefaults.homePageURLKey)
        #expect(BrowserNavigationDefaults.configuredHomePageURLString(userDefaults: userDefaults) == nil)
        #expect(BrowserNavigationDefaults.initialPageURLString(userDefaults: userDefaults) == "about:blank")
    }

    @Test func `closing a browser pane removes its browser session`() throws {
        let browserPane = PaneLeaf(content: .browser(BrowserSessionID()))
        let workspace = Workspace(
            title: "Workspace 1",
            root: .leaf(browserPane),
        )
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
        )

        let browserSessionID = try #require(browserPane.browserSessionID)
        #expect(model.browserSessions.session(for: browserSessionID) != nil)

        model.closePane(browserPane.id, in: workspace.id)

        #expect(model.browserSessions.session(for: browserSessionID) == nil)
        #expect(model.workspaces.first?.root == nil)
    }

    @Test func `splitting a focused pane into a browser pane creates a new browser session`() throws {
        let sourcePane = PaneLeaf()
        let workspace = Workspace(
            title: "Workspace 1",
            root: .leaf(sourcePane),
        )
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
        )

        let insertedPaneID = try #require(model.splitBrowserPane(sourcePane.id, in: workspace.id, direction: .right))
        let updatedWorkspace = try #require(model.workspaces.first(where: { $0.id == workspace.id }))
        let insertedPane = try #require(updatedWorkspace.root?.findPane(id: insertedPaneID))
        let insertedSessionID = try #require(insertedPane.browserSessionID)
        let insertedSession = try #require(model.browserSessions.session(for: insertedSessionID))

        #expect(updatedWorkspace.paneCount == 2)
        #expect(insertedSession.id == insertedSessionID)
        #expect(insertedSession.lastCommittedURL == nil)
        #expect(insertedSession.url == nil)
    }

    @Test func `duplicating a workspace remints browser session IDs and copies the last committed URL`() throws {
        let browserPane = PaneLeaf(content: .browser(BrowserSessionID()))
        let workspace = Workspace(
            title: "Workspace 1",
            root: .leaf(browserPane),
        )
        let model = WorkspaceStore(
            workspaces: [workspace],
            persistence: .inMemoryForTesting(),
        )

        let sourceSessionID = try #require(browserPane.browserSessionID)
        let sourceSession = try #require(model.browserSessions.session(for: sourceSessionID))
        sourceSession.title = "Docs"
        sourceSession.lastCommittedURL = "https://developer.apple.com/documentation/webkit/wkwebview"
        sourceSession.url = sourceSession.lastCommittedURL

        let duplicatedWorkspaceID = try #require(model.duplicateWorkspace(workspace.id))
        let duplicatedWorkspace = try #require(model.workspaces.first(where: { $0.id == duplicatedWorkspaceID }))
        let duplicatedPane = try #require(duplicatedWorkspace.root?.firstLeaf())
        let duplicatedSessionID = try #require(duplicatedPane.browserSessionID)
        let duplicatedSession = try #require(model.browserSessions.session(for: duplicatedSessionID))

        #expect(duplicatedSessionID != sourceSessionID)
        #expect(duplicatedSession.lastCommittedURL == sourceSession.lastCommittedURL)
        #expect(duplicatedSession.url == sourceSession.lastCommittedURL)
        #expect(duplicatedSession.title == sourceSession.title)
    }

    @Test func `workspace store loads the durable selected workspace for its window`() {
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

    @Test func `terminal host event parser recognizes prompt command and completion markers`() {
        var parser = TerminalHostEventParser()
        let output = ArraySlice(Array("\u{1B}]133;A\u{07}\u{1B}]133;C\u{07}\u{1B}]133;D;23\u{07}".utf8))

        let events = parser.ingest(output)

        #expect(events == [
            .shellIntegration(.promptStarted),
            .shellIntegration(.commandStarted),
            .shellIntegration(.commandFinished(exitStatus: 23)),
        ])
    }

    @Test func `terminal host event parser preserves incomplete sequences across chunks`() {
        var parser = TerminalHostEventParser()

        let firstEvents = parser.ingest(ArraySlice(Array("\u{1B}]133;".utf8)))
        let secondEvents = parser.ingest(ArraySlice(Array("A\u{07}\u{1B}]133;D;7\u{07}".utf8)))

        #expect(firstEvents.isEmpty)
        #expect(secondEvents == [
            .shellIntegration(.promptStarted),
            .shellIntegration(.commandFinished(exitStatus: 7)),
        ])
    }

    @Test func `terminal host event parser recognizes explicit terminal notifications`() {
        var parser = TerminalHostEventParser()
        let output = ArraySlice(Array("\u{1B}]777;notify;Build Finished;All tests passed\u{07}".utf8))

        let events = parser.ingest(output)

        #expect(events == [
            .notification(title: "Build Finished", body: "All tests passed"),
        ])
    }

    @Test func `terminal session updates shell phase and exit status from shell integration events`() {
        let session = TerminalSession(id: TerminalSessionID())

        session.applyShellIntegrationEvent(.promptStarted)
        #expect(session.shellPhase == .atPrompt)
        #expect(session.lastCommandExitStatus == nil)

        session.applyShellIntegrationEvent(.commandStarted)
        #expect(session.shellPhase == .runningCommand)

        session.applyShellIntegrationEvent(.commandFinished(exitStatus: 2))
        #expect(session.shellPhase == .atPrompt)
        #expect(session.lastCommandExitStatus == 2)
    }

    @Test func `terminal session records bells and explicit terminal notifications`() {
        let session = TerminalSession(id: TerminalSessionID())
        let receivedAt = Date(timeIntervalSince1970: 1_713_888_000)

        session.recordBell(at: receivedAt)
        session.recordAttentionNotification(
            title: "Build Finished",
            body: "All tests passed",
            at: receivedAt,
        )

        #expect(session.bellCount == 1)
        #expect(session.lastBellAt == receivedAt)
        #expect(session.lastAttentionNotification == TerminalAttentionNotification(
            title: "Build Finished",
            body: "All tests passed",
            receivedAt: receivedAt,
        ))
    }

    @Test func `terminal session clears active bell when the next command starts`() {
        let session = TerminalSession(id: TerminalSessionID())

        session.recordBell()
        #expect(session.hasActiveBell)

        session.applyShellIntegrationEvent(.commandStarted)

        #expect(!session.hasActiveBell)
        #expect(session.shellPhase == .runningCommand)
    }

    @Test func `terminal session can clear bell attention without resetting bell history`() {
        let session = TerminalSession(id: TerminalSessionID())

        session.recordBell()
        let bellCount = session.bellCount
        let lastBellAt = session.lastBellAt

        session.clearBellAttention()

        #expect(!session.hasActiveBell)
        #expect(session.bellCount == bellCount)
        #expect(session.lastBellAt == lastBellAt)
    }

    @Test func `workspace store tracks current bell counts per workspace and per window`() throws {
        let firstPane = PaneLeaf()
        let secondPane = PaneLeaf()
        let firstWorkspace = Workspace(title: "Workspace 1", root: .leaf(firstPane))
        let secondWorkspace = Workspace(title: "Workspace 2", root: .leaf(secondPane))
        let model = WorkspaceStore(
            workspaces: [firstWorkspace, secondWorkspace],
            persistence: .inMemoryForTesting(),
        )

        let firstSessionID = try #require(firstPane.terminalSessionID)
        let secondSessionID = try #require(secondPane.terminalSessionID)
        let firstSession = try #require(model.sessions.session(for: firstSessionID))
        let secondSession = try #require(model.sessions.session(for: secondSessionID))

        firstSession.recordBell()
        secondSession.recordBell()
        model.refreshBellCounts()

        #expect(model.currentBellCount(for: firstWorkspace.id) == 1)
        #expect(model.currentBellCount(for: secondWorkspace.id) == 1)
        #expect(model.currentWindowBellCount == 2)

        firstSession.applyShellIntegrationEvent(.commandStarted)
        model.refreshBellCounts()

        #expect(model.currentBellCount(for: firstWorkspace.id) == 0)
        #expect(model.currentBellCount(for: secondWorkspace.id) == 1)
        #expect(model.currentWindowBellCount == 1)
    }
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
