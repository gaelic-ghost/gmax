import Foundation
import OSLog
import SwiftUI

// MARK: - Pane Lifecycle

// MARK: Pane creation, relaunch, focus, split, close, and split-fraction updates.

extension WorkspaceStore {
    @discardableResult
    func createPane(in workspaceID: WorkspaceID) -> PaneID? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }

        let workspace = workspaces[workspaceIndex]

        if workspace.root == nil {
            let pane = PaneLeaf()
            workspaces[workspaceIndex].root = .leaf(pane)
            _ = sessions.ensureSession(
                id: pane.sessionID,
                launchConfiguration: launchContextBuilder.makeLaunchConfiguration(),
            )
            schedulePersistenceSave()
            return pane.id
        }

        guard let paneID = workspace.root?.firstLeaf()?.id else {
            return nil
        }

        return splitPane(paneID, in: workspace.id, direction: .right)
    }

    func relaunchPane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }

        let workspace = workspaces[workspaceIndex]
        guard let pane = workspace.root?.findPane(id: paneID) else {
            Logger.pane.error("The app was asked to relaunch a pane, but the target pane could not be resolved inside the selected workspace. The relaunch request was dropped before any shell state changed. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). Pane ID: \(paneID.rawValue.uuidString, privacy: .public)")
            return
        }

        let session = sessions.ensureSession(id: pane.sessionID)
        session.prepareForRelaunch()
        Logger.pane.notice("Requested a shell relaunch for the focused pane in a live workspace. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). Pane ID: \(paneID.rawValue.uuidString, privacy: .public). Session ID: \(session.id.rawValue.uuidString, privacy: .public)")
    }

    @discardableResult
    func splitPane(_ paneID: PaneID, in workspaceID: WorkspaceID, direction: SplitDirection) -> PaneID? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }
        guard var root = workspaces[workspaceIndex].root else {
            return nil
        }
        guard let sourcePane = root.findPane(id: paneID) else {
            return nil
        }

        let sourceSession = sessions.ensureSession(id: sourcePane.sessionID)
        let inheritedCurrentDirectory = sourceSession.currentDirectory
            ?? sourceSession.launchConfiguration.currentDirectory

        let newPane = PaneLeaf()
        guard root.split(
            paneID: paneID,
            direction: direction,
            newPane: newPane,
        ) else {
            return nil
        }

        workspaces[workspaceIndex].root = root
        _ = sessions.ensureSession(
            id: newPane.sessionID,
            launchConfiguration: launchContextBuilder.makeLaunchConfiguration(
                currentDirectory: inheritedCurrentDirectory,
            ),
        )
        schedulePersistenceSave()
        return newPane.id
    }

    @discardableResult
    func closePane(_ paneID: PaneID, in workspaceID: WorkspaceID) -> PaneID? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }
        guard let root = workspaces[workspaceIndex].root else {
            return nil
        }

        let priorLeaves = root.leaves()
        guard priorLeaves.contains(where: { $0.id == paneID }) else {
            return nil
        }

        // Pick the fallback from the pane tree shape rather than flat leaf order.
        // If the closed pane was one side of a split and the opposite branch survives,
        // focus the nearest leaf in that surviving sibling branch. When the closed pane
        // lived deeper in the tree, recurse until the removal reaches the closest split
        // that has to collapse, then use the structurally adjacent survivor from there.
        // This keeps close behavior tied to the pane ancestry that produced the split,
        // instead of jumping to an unrelated pane that only happened to survive at a
        // similar linear index in the leaf list.
        let removal = root.removingPaneWithFallback(id: paneID)
        let updatedRoot = removal.node
        let survivingLeaves = updatedRoot?.leaves() ?? []
        workspaces[workspaceIndex].root = updatedRoot
        removeUnreferencedSessions()

        guard !survivingLeaves.isEmpty else {
            schedulePersistenceSave()
            return nil
        }

        schedulePersistenceSave()
        return removal.fallbackPaneID ?? survivingLeaves.last?.id
    }

    func setSplitFraction(_ fraction: CGFloat, for splitID: SplitID, in workspaceID: WorkspaceID) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }
        guard var root = workspaces[workspaceIndex].root else {
            return
        }
        guard root.updateSplitFraction(splitID: splitID, fraction: fraction) else {
            return
        }

        workspaces[workspaceIndex].root = root
        schedulePersistenceSave()
    }
}

extension WorkspaceStore {
    func removeUnreferencedSessions() {
        let activeLeaves = workspaces.flatMap { workspace in
            (workspace.root?.leaves() ?? []).map { (workspace.id, $0) }
        }
        let activeSessionIDs = Set(activeLeaves.map(\.1.sessionID))
        sessions.removeSessions(notIn: activeSessionIDs)
        paneControllers.removeControllers(notIn: Set(activeLeaves.map(\.1.id)))
    }
}
