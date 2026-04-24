import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var workspaces: [Workspace]
    @Published var recentlyClosedWorkspaceCount = 0

    let sceneIdentity: WorkspaceSceneIdentity
    let persistence: WorkspacePersistenceController
    let launchContextBuilder: TerminalLaunchContextBuilder
    let sessions: TerminalSessionRegistry
    let browserSessions: BrowserSessionRegistry
    let paneControllers: TerminalPaneControllerStore
    let browserPaneControllers: BrowserPaneControllerStore
    var persistedSelectedWorkspaceID: WorkspaceID?
    var pendingPersistenceTask: Task<Void, Never>?

    init(
        sceneIdentity: WorkspaceSceneIdentity = WorkspaceSceneIdentity(),
        workspaces: [Workspace]? = nil,
        persistence: WorkspacePersistenceController? = nil,
        launchContextBuilder: TerminalLaunchContextBuilder? = nil,
    ) {
        UserDefaults.standard.register(
            defaults: [
                WorkspacePersistenceDefaults.restoreWorkspacesOnLaunchKey:
                    WorkspacePersistenceDefaults.systemRestoresWindowsByDefault(),
                WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey: true,
                WorkspacePersistenceDefaults.autoSaveClosedItemsKey: false,
                WorkspacePersistenceDefaults.backgroundSaveIntervalMinutesKey:
                    WorkspacePersistenceDefaults.defaultBackgroundSaveIntervalMinutes,
            ],
        )
        let persistence = persistence ?? .shared
        let launchContextBuilder = launchContextBuilder ?? .live()
        let resolvedWorkspaces: [Workspace]
        let resolvedPaneSnapshotsBySessionID: [TerminalSessionID: WorkspaceSessionSnapshot]
        let resolvedBrowserSnapshotsBySessionID: [BrowserSessionID: BrowserSessionSnapshot]
        let resolvedRecentlyClosedWorkspaceCount: Int
        let resolvedWindowState: WorkspaceWindowStateSnapshot?

        if let workspaces {
            resolvedWorkspaces = workspaces
            resolvedPaneSnapshotsBySessionID = [:]
            resolvedBrowserSnapshotsBySessionID = [:]
            resolvedRecentlyClosedWorkspaceCount = 0
            resolvedWindowState = nil
        } else {
            let shouldRestorePersistedWorkspaces = WorkspacePersistenceDefaults.restoreWorkspacesOnLaunch()
            let persistedWorkspaceRevisions = shouldRestorePersistedWorkspaces
                ? persistence.loadWorkspaceRevisions(for: sceneIdentity)
                : []
            let persistedWorkspaces = persistedWorkspaceRevisions.map(\.workspace)
            resolvedRecentlyClosedWorkspaceCount = shouldRestorePersistedWorkspaces
                ? persistence.countRecentWorkspaceHistory(for: sceneIdentity)
                : 0
            resolvedWindowState = shouldRestorePersistedWorkspaces
                ? persistence.loadWindowState(for: sceneIdentity)
                : nil
            resolvedPaneSnapshotsBySessionID = Dictionary(
                persistedWorkspaceRevisions.flatMap { revision in
                    revision.paneSnapshotsBySessionID
                },
                uniquingKeysWith: { _, newest in newest },
            )
            resolvedBrowserSnapshotsBySessionID = Dictionary(
                persistedWorkspaceRevisions.flatMap { revision in
                    revision.browserSnapshotsBySessionID
                },
                uniquingKeysWith: { _, newest in newest },
            )
            if persistedWorkspaces.isEmpty {
                let pane = PaneLeaf()
                resolvedWorkspaces = [Workspace(title: "Workspace 1", root: .leaf(pane))]
            } else {
                resolvedWorkspaces = persistedWorkspaces
            }

            if shouldRestorePersistedWorkspaces, !persistedWorkspaces.isEmpty {
                Logger.app.notice("Restored persisted workspaces during app launch. Restored workspace count: \(persistedWorkspaces.count)")
            } else if shouldRestorePersistedWorkspaces {
                Logger.app.notice("Workspace restoration is enabled for launch, but there were no persisted workspaces to restore. The app started with the default workspace instead.")
            } else {
                Logger.app.notice("Workspace restoration on launch is disabled, so the app started with the default workspace state for this session.")
            }
        }

        self.sceneIdentity = sceneIdentity
        self.persistence = persistence
        self.launchContextBuilder = launchContextBuilder
        sessions = TerminalSessionRegistry(
            workspaces: resolvedWorkspaces,
            defaultLaunchConfiguration: launchContextBuilder.makeLaunchConfiguration(),
            restoredPaneSnapshotsBySessionID: resolvedPaneSnapshotsBySessionID,
        )
        browserSessions = BrowserSessionRegistry(
            workspaces: resolvedWorkspaces,
            restoredSnapshotsBySessionID: resolvedBrowserSnapshotsBySessionID,
        )
        paneControllers = TerminalPaneControllerStore()
        browserPaneControllers = BrowserPaneControllerStore()
        self.workspaces = resolvedWorkspaces
        recentlyClosedWorkspaceCount = resolvedRecentlyClosedWorkspaceCount
        persistedSelectedWorkspaceID = resolvedWindowState?.selectedWorkspaceID
    }
}
