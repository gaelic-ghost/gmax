import Combine
import Foundation
import OSLog
import SwiftUI

enum WorkspacePersistenceSaveReason: String {
    case workspaceCreated
    case workspaceRenamed
    case workspaceDuplicated
    case workspaceClosed
    case workspaceDeleted
    case workspaceUndoClose
    case workspaceOpenedFromLibrary
    case paneCreated
    case paneSplit
    case paneClosed
    case paneSplitFractionChanged
    case appWillTerminate
    case sceneBecameInactive
    case sceneEnteredBackground
    case windowBecameActive
    case windowResignedActive
    case windowDisappeared
    case backgroundIntervalElapsed
    case unitTestImmediateFlush

    var logName: String { rawValue }
}

enum LibraryOpenResult: Equatable {
    case workspace(WorkspaceID)
    case window(WorkspaceSceneIdentity)
}

// MARK: - Workspace Lifecycle

// MARK: Workspace creation, duplication, close, restore, and library persistence flows.

extension WorkspaceStore {
    @discardableResult
    func createWorkspace() -> WorkspaceID {
        let pane = PaneLeaf()
        let workspace = Workspace(
            title: uniqueWorkspaceTitle(startingWith: "Workspace \(workspaces.count + 1)"),
            root: .leaf(pane),
        )

        workspaces.append(workspace)
        _ = sessions.ensureSession(
            id: pane.sessionID,
            launchConfiguration: launchContextBuilder.makeLaunchConfiguration(),
        )
        Logger.workspace.notice("Created a new workspace and seeded it with an initial pane. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
        schedulePersistenceSave(reason: .workspaceCreated)
        return workspace.id
    }

    func renameWorkspace(_ workspaceID: WorkspaceID, to proposedTitle: String) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }

        let trimmedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            return
        }

        let previousTitle = workspaces[workspaceIndex].title
        workspaces[workspaceIndex].title = trimmedTitle
        Logger.workspace.notice("Renamed a workspace. Previous title: \(previousTitle, privacy: .public). New title: \(trimmedTitle, privacy: .public). Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
        schedulePersistenceSave(reason: .workspaceRenamed)
    }

    @discardableResult
    func duplicateWorkspace(_ workspaceID: WorkspaceID) -> WorkspaceID? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }

        let workspace = workspaces[workspaceIndex]
        let duplicatedWorkspace = Workspace(
            title: uniqueWorkspaceTitle(startingWith: "\(workspace.title) Copy"),
            root: workspace.root.map { duplicateNode($0) },
        )
        workspaces.insert(duplicatedWorkspace, at: workspaceIndex + 1)
        Logger.workspace.notice("Duplicated a workspace layout into a new workspace. Source workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). New workspace title: \(duplicatedWorkspace.title, privacy: .public). New workspace ID: \(duplicatedWorkspace.id.rawValue.uuidString, privacy: .public)")
        schedulePersistenceSave(reason: .workspaceDuplicated)
        return duplicatedWorkspace.id
    }

    func closeWorkspace(_ workspaceID: WorkspaceID) -> WorkspaceID? {
        removeWorkspace(
            workspaceID,
            recordRecentlyClosed: UserDefaults.standard.bool(
                forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey,
            ),
            saveToLibrary: UserDefaults.standard.bool(
                forKey: WorkspacePersistenceDefaults.autoSaveClosedWorkspacesKey,
            ),
        )
    }

    func deleteWorkspace(_ workspaceID: WorkspaceID) {
        guard workspaces.count > 1, workspaces.contains(where: { $0.id == workspaceID }) else {
            return
        }

        _ = removeWorkspace(
            workspaceID,
            recordRecentlyClosed: false,
            saveToLibrary: false,
        )
    }

    @discardableResult
    func undoCloseWorkspace() -> WorkspaceID? {
        guard let closedWorkspace = persistence.consumeMostRecentWorkspaceInRecentHistory(for: sceneIdentity) else {
            return nil
        }

        let insertionIndex = min(closedWorkspace.formerIndex, workspaces.count)
        workspaces.insert(closedWorkspace.revision.workspace, at: insertionIndex)

        for leaf in closedWorkspace.revision.workspace.root?.leaves() ?? [] {
            let paneSnapshot = closedWorkspace.revision.paneSnapshotsBySessionID[leaf.sessionID]
            let launchConfiguration = paneSnapshot?.launchConfiguration
                ?? launchContextBuilder.makeLaunchConfiguration()
            let session = sessions.ensureSession(id: leaf.sessionID, launchConfiguration: launchConfiguration)
            session.title = paneSnapshot?.title ?? session.title
            session.currentDirectory = launchConfiguration.currentDirectory
            session.setRestoredTranscript(paneSnapshot?.transcript)
        }

        refreshRecentlyClosedWorkspaceCount()
        Logger.workspace.notice("Reopened the most recently closed workspace from durable window-scoped persistence. Workspace title: \(closedWorkspace.revision.workspace.title, privacy: .public). Workspace ID: \(closedWorkspace.revision.workspace.id.rawValue.uuidString, privacy: .public)")
        schedulePersistenceSave(reason: .workspaceUndoClose)
        return closedWorkspace.revision.workspace.id
    }

    func clearRecentlyClosedWorkspaces() {
        persistence.clearRecentWorkspaceHistory(for: sceneIdentity)
        refreshRecentlyClosedWorkspaceCount()
        Logger.workspace.notice("Cleared durable recently closed workspace history for the current window.")
    }

    @discardableResult
    func saveWorkspaceToLibrary(
        _ workspaceID: WorkspaceID,
        transcriptsBySessionID: [TerminalSessionID: String] = [:],
    ) -> LibraryItemListing? {
        guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
            Logger.workspace.error("The app was asked to save a workspace to the library, but that workspace no longer exists in the current shell model. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
            return nil
        }

        let resolvedTranscripts = captureWorkspaceTranscripts(
            for: workspace,
            explicitTranscriptsBySessionID: transcriptsBySessionID,
        )

        let summary = persistence.saveWorkspaceToLibrary(
            from: workspace,
            sessions: sessions,
            transcriptsBySessionID: resolvedTranscripts,
        )
        if let summary {
            objectWillChange.send()
            Logger.workspace.notice("Saved a workspace to the library. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public). Library item ID: \(summary.id.uuidString, privacy: .public)")
        }
        return summary
    }

    func listLibraryItems(matching query: String? = nil) -> [LibraryItemListing] {
        persistence.listLibraryItems(matching: query)
    }

    @discardableResult
    func closeWorkspaceToLibrary(
        _ workspaceID: WorkspaceID,
        transcriptsBySessionID: [TerminalSessionID: String] = [:],
    ) -> WorkspaceID? {
        removeWorkspace(
            workspaceID,
            recordRecentlyClosed: UserDefaults.standard.bool(
                forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey,
            ),
            saveToLibrary: true,
            explicitTranscriptsBySessionID: transcriptsBySessionID,
        )
    }

    @discardableResult
    func openLibraryItem(_ libraryItemID: UUID) -> LibraryOpenResult? {
        guard let libraryItem = persistence.loadLibraryItemListing(id: libraryItemID) else {
            Logger.workspace.error("The app could not reopen a library item because the requested entry was missing or unreadable. Check the persistence logs for the exact load failure. Library item ID: \(libraryItemID.uuidString, privacy: .public)")
            return nil
        }

        switch libraryItem.kind {
            case .workspace:
                return openWorkspaceLibraryItem(libraryItemID)
                    .map(LibraryOpenResult.workspace)
            case .window:
                guard let sceneIdentity = libraryItem.windowID else {
                    Logger.workspace.error("The app could not reopen a saved window because the library item was missing its durable window identity. Library item ID: \(libraryItemID.uuidString, privacy: .public)")
                    return nil
                }

                persistence.markLibraryItemOpened(libraryItemID)
                Logger.workspace.notice("Opened a saved window from the library. Library item ID: \(libraryItemID.uuidString, privacy: .public). Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public)")
                return .window(sceneIdentity)
        }
    }

    func deleteLibraryItem(_ libraryItemID: UUID) {
        guard persistence.deleteLibraryItem(id: libraryItemID) else {
            Logger.workspace.error("The app could not delete a library item because persistence did not confirm the deletion. Check the persistence logs for the exact failure. Library item ID: \(libraryItemID.uuidString, privacy: .public)")
            return
        }

        objectWillChange.send()
        Logger.workspace.notice("Deleted a library item. Library item ID: \(libraryItemID.uuidString, privacy: .public)")
    }
}

// MARK: - Workspace Helpers

// MARK: Internal helpers that support workspace cloning, restore, close, and persistence workflows.

extension WorkspaceStore {
    private struct PersistenceSnapshot {
        let liveWorkspaces: [Workspace]
        let selectedWorkspaceID: WorkspaceID?
        let liveTranscriptsByWorkspaceID: [WorkspaceID: [TerminalSessionID: String]]
    }

    private func uniqueWorkspaceTitle(startingWith baseTitle: String) -> String {
        let normalizedBaseTitle = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseTitle = normalizedBaseTitle.isEmpty ? "Workspace" : normalizedBaseTitle
        let existingTitles = Set(workspaces.map(\.title))
        guard existingTitles.contains(resolvedBaseTitle) else {
            return resolvedBaseTitle
        }

        var suffix = 2
        while true {
            let candidate = "\(resolvedBaseTitle) \(suffix)"
            if !existingTitles.contains(candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    private func openWorkspaceLibraryItem(_ libraryItemID: UUID) -> WorkspaceID? {
        guard let savedWorkspace = persistence.loadWorkspaceLibraryItem(id: libraryItemID) else {
            Logger.workspace.error("The app could not reopen a workspace from the library because the requested library item was missing or unreadable. Check the persistence logs for the exact load failure. Library item ID: \(libraryItemID.uuidString, privacy: .public)")
            return nil
        }

        if workspaces.contains(where: { $0.id == savedWorkspace.workspace.id }) {
            persistence.markLibraryItemOpened(libraryItemID)
            Logger.workspace.notice("Requested a workspace library item, but that workspace is already live in the current shell model. Reusing the existing workspace identity. Library item ID: \(libraryItemID.uuidString, privacy: .public). Workspace ID: \(savedWorkspace.workspace.id.rawValue.uuidString, privacy: .public)")
            return savedWorkspace.workspace.id
        }

        var launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration] = [:]
        var transcriptsBySessionID: [TerminalSessionID: String] = [:]
        var titlesBySessionID: [TerminalSessionID: String] = [:]
        let restoredWorkspace = Workspace(
            id: WorkspaceID(rawValue: savedWorkspace.id),
            title: {
                let title = savedWorkspace.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let baseTitle = title.isEmpty ? "Workspace" : title
                return uniqueWorkspaceTitle(startingWith: baseTitle)
            }(),
            root: savedWorkspace.workspace.root.map {
                restoreNode(
                    $0,
                    paneSnapshotsBySessionID: savedWorkspace.paneSnapshotsBySessionID,
                    launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
                    transcriptsBySessionID: &transcriptsBySessionID,
                    titlesBySessionID: &titlesBySessionID,
                )
            },
        )
        workspaces.append(restoredWorkspace)

        for (sessionID, launchConfiguration) in launchConfigurationsBySessionID {
            let session = sessions.ensureSession(id: sessionID, launchConfiguration: launchConfiguration)
            session.title = titlesBySessionID[sessionID] ?? "Shell"
            session.currentDirectory = launchConfiguration.currentDirectory
            session.setRestoredTranscript(transcriptsBySessionID[sessionID])
        }

        persistence.markLibraryItemOpened(libraryItemID)
        Logger.workspace.notice("Opened a workspace from a library item. Workspace title: \(savedWorkspace.title, privacy: .public). Library item ID: \(libraryItemID.uuidString, privacy: .public). Workspace ID: \(restoredWorkspace.id.rawValue.uuidString, privacy: .public). Restored pane count: \((restoredWorkspace.root?.leaves().count ?? 0))")
        schedulePersistenceSave(reason: .workspaceOpenedFromLibrary)
        return restoredWorkspace.id
    }

    private func duplicateNode(_ node: PaneNode) -> PaneNode {
        switch node {
            case let .leaf(leaf):
                let sourceSession = sessions.ensureSession(id: leaf.sessionID)
                let inheritedCurrentDirectory = sourceSession.currentDirectory
                    ?? sourceSession.launchConfiguration.currentDirectory
                let clonedLeaf = PaneLeaf()
                _ = sessions.ensureSession(
                    id: clonedLeaf.sessionID,
                    launchConfiguration: launchContextBuilder.makeLaunchConfiguration(
                        currentDirectory: inheritedCurrentDirectory,
                    ),
                )
                return .leaf(clonedLeaf)

            case let .split(split):
                return .split(
                    PaneSplit(
                        axis: split.axis,
                        fraction: split.fraction,
                        first: duplicateNode(split.first),
                        second: duplicateNode(split.second),
                    ),
                )
        }
    }

    private func makePersistenceSnapshot() -> PersistenceSnapshot {
        let workspacesSnapshot = workspaces
        let transcriptsByWorkspaceID = Dictionary(
            uniqueKeysWithValues: workspacesSnapshot.map { workspace in
                (
                    workspace.id,
                    captureWorkspaceTranscripts(
                        for: workspace,
                        explicitTranscriptsBySessionID: [:],
                    ),
                )
            },
        )

        return PersistenceSnapshot(
            liveWorkspaces: workspacesSnapshot,
            selectedWorkspaceID: persistedSelectedWorkspaceID,
            liveTranscriptsByWorkspaceID: transcriptsByWorkspaceID,
        )
    }

    private func persistSceneState(
        snapshot: PersistenceSnapshot,
        reason: WorkspacePersistenceSaveReason,
        delivery: String,
    ) {
        let windowID = sceneIdentity.windowID.uuidString
        let recentlyClosedCount = recentlyClosedWorkspaceCount
        Logger.persistence.notice(
            "Persisting the current window-scoped live workspace state. Delivery: \(delivery, privacy: .public). Reason: \(reason.logName, privacy: .public). Window ID: \(windowID, privacy: .public). Live workspace count: \(snapshot.liveWorkspaces.count). Recently closed count: \(recentlyClosedCount).",
        )
        persistence.saveSceneState(
            for: sceneIdentity,
            liveWorkspaces: snapshot.liveWorkspaces,
            selectedWorkspaceID: snapshot.selectedWorkspaceID,
            sessions: sessions,
            liveTranscriptsByWorkspaceID: snapshot.liveTranscriptsByWorkspaceID,
        )
    }

    func persistSceneStateNow(reason: WorkspacePersistenceSaveReason) {
        pendingPersistenceTask?.cancel()
        let snapshot = makePersistenceSnapshot()
        persistSceneState(
            snapshot: snapshot,
            reason: reason,
            delivery: "immediate",
        )
    }

    func schedulePersistenceSave(reason: WorkspacePersistenceSaveReason) {
        pendingPersistenceTask?.cancel()
        let snapshot = makePersistenceSnapshot()
        pendingPersistenceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else {
                return
            }

            persistSceneState(
                snapshot: snapshot,
                reason: reason,
                delivery: "debounced",
            )
        }
    }

    @discardableResult
    func removeWorkspace(
        _ workspaceID: WorkspaceID,
        recordRecentlyClosed: Bool,
        saveToLibrary: Bool,
        explicitTranscriptsBySessionID: [TerminalSessionID: String] = [:],
    ) -> WorkspaceID? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }

        let workspace = workspaces[workspaceIndex]
        if saveToLibrary {
            let resolvedTranscripts = captureWorkspaceTranscripts(
                for: workspace,
                explicitTranscriptsBySessionID: explicitTranscriptsBySessionID,
            )
            _ = persistence.saveWorkspaceToLibrary(
                from: workspace,
                sessions: sessions,
                transcriptsBySessionID: resolvedTranscripts,
            )
        }

        if recordRecentlyClosed {
            recordRecentlyClosedWorkspace(workspace, formerIndex: workspaceIndex)
        } else {
            persistence.removeWorkspaceFromWindowHistory(workspaceID, for: sceneIdentity)
            refreshRecentlyClosedWorkspaceCount()
        }

        workspaces.remove(at: workspaceIndex)
        removeUnreferencedSessions()

        let nextSelectedWorkspaceID = workspaces.isEmpty ? nil : workspaces[min(workspaceIndex, workspaces.count - 1)].id

        Logger.workspace.notice("Closed a workspace from the live shell. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public). Recorded in recently closed: \(recordRecentlyClosed). Saved to library: \(saveToLibrary)")
        let saveReason: WorkspacePersistenceSaveReason = recordRecentlyClosed || saveToLibrary
            ? .workspaceClosed
            : .workspaceDeleted
        schedulePersistenceSave(reason: saveReason)
        return nextSelectedWorkspaceID
    }

    private func recordRecentlyClosedWorkspace(_ workspace: Workspace, formerIndex: Int) {
        guard UserDefaults.standard.bool(forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey) else {
            return
        }

        let launchConfigurationsBySessionID = Dictionary(uniqueKeysWithValues: (workspace.root?.leaves() ?? []).map { leaf in
            let session = sessions.ensureSession(id: leaf.sessionID)
            let currentDirectory = session.currentDirectory ?? session.launchConfiguration.currentDirectory
            let launchConfiguration = launchContextBuilder.makeLaunchConfiguration(
                currentDirectory: currentDirectory,
            )
            return (leaf.sessionID, launchConfiguration)
        })
        let titlesBySessionID = Dictionary(uniqueKeysWithValues: (workspace.root?.leaves() ?? []).map { leaf in
            let session = sessions.ensureSession(id: leaf.sessionID)
            return (leaf.sessionID, session.title)
        })
        let transcriptsBySessionID = captureWorkspaceTranscripts(
            for: workspace,
            explicitTranscriptsBySessionID: [:],
        )

        persistence.recordWorkspaceInRecentHistory(
            WindowWorkspaceHistoryInput(
                workspace: workspace,
                formerIndex: formerIndex,
                launchConfigurationsBySessionID: launchConfigurationsBySessionID,
                titlesBySessionID: titlesBySessionID,
                transcriptsBySessionID: transcriptsBySessionID,
            ),
            for: sceneIdentity,
            limit: WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount,
        )
        refreshRecentlyClosedWorkspaceCount()
    }

    private func refreshRecentlyClosedWorkspaceCount() {
        recentlyClosedWorkspaceCount = persistence.countRecentWorkspaceHistory(for: sceneIdentity)
    }

    private func captureWorkspaceTranscripts(
        for workspace: Workspace,
        explicitTranscriptsBySessionID: [TerminalSessionID: String],
    ) -> [TerminalSessionID: String] {
        var resolvedTranscripts = explicitTranscriptsBySessionID

        for leaf in workspace.root?.leaves() ?? [] where resolvedTranscripts[leaf.sessionID] == nil {
            guard let transcript = paneControllers.existingController(for: leaf.id)?.captureTranscript() else {
                continue
            }

            resolvedTranscripts[leaf.sessionID] = transcript
        }

        return resolvedTranscripts
    }

    private func restoreNode(
        _ node: PaneNode,
        paneSnapshotsBySessionID: [TerminalSessionID: WorkspaceSessionSnapshot],
        launchConfigurationsBySessionID: inout [TerminalSessionID: TerminalLaunchConfiguration],
        transcriptsBySessionID: inout [TerminalSessionID: String],
        titlesBySessionID: inout [TerminalSessionID: String],
    ) -> PaneNode {
        switch node {
            case let .leaf(leaf):
                let restoredLeaf = PaneLeaf()
                let paneSnapshot = paneSnapshotsBySessionID[leaf.sessionID]
                let launchConfiguration = paneSnapshot?.launchConfiguration
                    ?? launchContextBuilder.makeLaunchConfiguration()
                launchConfigurationsBySessionID[restoredLeaf.sessionID] = launchConfiguration
                if let transcript = paneSnapshot?.transcript {
                    transcriptsBySessionID[restoredLeaf.sessionID] = transcript
                }
                if let title = paneSnapshot?.title {
                    titlesBySessionID[restoredLeaf.sessionID] = title
                }
                return .leaf(restoredLeaf)

            case let .split(split):
                return .split(
                    PaneSplit(
                        axis: split.axis,
                        fraction: split.fraction,
                        first: restoreNode(
                            split.first,
                            paneSnapshotsBySessionID: paneSnapshotsBySessionID,
                            launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
                            transcriptsBySessionID: &transcriptsBySessionID,
                            titlesBySessionID: &titlesBySessionID,
                        ),
                        second: restoreNode(
                            split.second,
                            paneSnapshotsBySessionID: paneSnapshotsBySessionID,
                            launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
                            transcriptsBySessionID: &transcriptsBySessionID,
                            titlesBySessionID: &titlesBySessionID,
                        ),
                    ),
                )
        }
    }
}
