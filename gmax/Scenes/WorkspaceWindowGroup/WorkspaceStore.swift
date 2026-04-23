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
    let paneControllers: TerminalPaneControllerStore
    var persistedSelectedWorkspaceID: WorkspaceID?
    var pendingPersistenceTask: Task<Void, Never>?
    var recentlyClosedWorkspaces: [RecentlyClosedWorkspace] = []

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
                WorkspacePersistenceDefaults.autoSaveClosedWorkspacesKey: false,
                WorkspacePersistenceDefaults.backgroundSaveIntervalMinutesKey:
                    WorkspacePersistenceDefaults.defaultBackgroundSaveIntervalMinutes,
            ],
        )
        let persistence = persistence ?? .shared
        let launchContextBuilder = launchContextBuilder ?? .live()
        let resolvedWorkspaces: [Workspace]
        let resolvedRecentlyClosedWorkspaces: [RecentlyClosedWorkspace]
        let resolvedWindowState: WorkspaceWindowStateSnapshot?

        if let workspaces {
            resolvedWorkspaces = workspaces
            resolvedRecentlyClosedWorkspaces = []
            resolvedWindowState = nil
        } else {
            let shouldRestorePersistedWorkspaces = WorkspacePersistenceDefaults.restoreWorkspacesOnLaunch()
            let persistedWorkspaces = shouldRestorePersistedWorkspaces
                ? persistence.loadWorkspaces(for: sceneIdentity)
                : []
            let persistedRecentlyClosedWorkspaces = shouldRestorePersistedWorkspaces
                ? persistence.loadRecentlyClosedWorkspaces(for: sceneIdentity)
                : []
            resolvedWindowState = shouldRestorePersistedWorkspaces
                ? persistence.loadWindowState(for: sceneIdentity)
                : nil
            if persistedWorkspaces.isEmpty {
                let pane = PaneLeaf()
                resolvedWorkspaces = [Workspace(title: "Workspace 1", root: .leaf(pane))]
            } else {
                resolvedWorkspaces = persistedWorkspaces
            }
            resolvedRecentlyClosedWorkspaces = persistedRecentlyClosedWorkspaces.map { persistedWorkspace in
                RecentlyClosedWorkspace(
                    workspace: persistedWorkspace.revision.workspace,
                    formerIndex: persistedWorkspace.formerIndex,
                    launchConfigurationsBySessionID: Dictionary(
                        uniqueKeysWithValues: persistedWorkspace.revision.paneSnapshotsBySessionID.map {
                            ($0.key, $0.value.launchConfiguration)
                        },
                    ),
                    titlesBySessionID: Dictionary(
                        uniqueKeysWithValues: persistedWorkspace.revision.paneSnapshotsBySessionID.map {
                            ($0.key, $0.value.title)
                        },
                    ),
                    transcriptsBySessionID: Dictionary(
                        uniqueKeysWithValues: persistedWorkspace.revision.paneSnapshotsBySessionID.compactMap {
                            guard let transcript = $0.value.transcript else {
                                return nil
                            }

                            return ($0.key, transcript)
                        },
                    ),
                )
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
        )
        paneControllers = TerminalPaneControllerStore()
        self.workspaces = resolvedWorkspaces
        recentlyClosedWorkspaces = resolvedRecentlyClosedWorkspaces
        recentlyClosedWorkspaceCount = resolvedRecentlyClosedWorkspaces.count
        persistedSelectedWorkspaceID = resolvedWindowState?.selectedWorkspaceID
    }
}
