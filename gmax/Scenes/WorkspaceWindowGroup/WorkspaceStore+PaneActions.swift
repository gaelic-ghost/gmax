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
            if let sessionID = pane.terminalSessionID {
                _ = sessions.ensureSession(
                    id: sessionID,
                    launchConfiguration: launchContextBuilder.makeLaunchConfiguration(),
                )
            }
            reconcileTerminalSessionObservations()
            schedulePersistenceSave(reason: .paneCreated)
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
        guard let sessionID = pane.terminalSessionID else {
            Logger.pane.error("The app was asked to relaunch a pane, but that pane does not currently host a terminal session. The relaunch request was dropped before any session state changed. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). Pane ID: \(paneID.rawValue.uuidString, privacy: .public)")
            return
        }

        let session = sessions.ensureSession(id: sessionID)
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
        guard let sourceSessionID = sourcePane.terminalSessionID else {
            Logger.pane.error("The app was asked to split a pane and inherit terminal launch state, but the source pane does not currently host a terminal session. The split request was dropped before any pane-tree state changed. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). Pane ID: \(paneID.rawValue.uuidString, privacy: .public)")
            return nil
        }

        let sourceSession = sessions.ensureSession(id: sourceSessionID)
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
        if let sessionID = newPane.terminalSessionID {
            _ = sessions.ensureSession(
                id: sessionID,
                launchConfiguration: launchContextBuilder.makeLaunchConfiguration(
                    currentDirectory: inheritedCurrentDirectory,
                ),
            )
        }
        reconcileTerminalSessionObservations()
        schedulePersistenceSave(reason: .paneSplit)
        return newPane.id
    }

    @discardableResult
    func splitBrowserPane(_ paneID: PaneID, in workspaceID: WorkspaceID, direction: SplitDirection) -> PaneID? {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return nil
        }
        guard var root = workspaces[workspaceIndex].root else {
            return nil
        }
        guard root.findPane(id: paneID) != nil else {
            return nil
        }

        let newPane = PaneLeaf(content: .browser(BrowserSessionID()))
        guard root.split(
            paneID: paneID,
            direction: direction,
            newPane: newPane,
        ) else {
            return nil
        }

        workspaces[workspaceIndex].root = root
        reconcileTerminalSessionObservations()
        if let sessionID = newPane.browserSessionID {
            _ = browserSessions.ensureSession(id: sessionID)
        }
        schedulePersistenceSave(reason: .paneSplit)
        return newPane.id
    }

    func closePane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
        guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            return
        }
        guard let root = workspaces[workspaceIndex].root else {
            return
        }

        let priorLeaves = root.leaves()
        guard priorLeaves.contains(where: { $0.id == paneID }) else {
            return
        }

        workspaces[workspaceIndex].root = root.removingPane(id: paneID)
        removeUnreferencedPaneRuntime()
        schedulePersistenceSave(reason: .paneClosed)
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
        schedulePersistenceSave(reason: .paneSplitFractionChanged)
    }
}

extension WorkspaceStore {
    func removeUnreferencedPaneRuntime() {
        let activeLeaves = workspaces.flatMap { workspace in
            (workspace.root?.leaves() ?? []).map { (workspace.id, $0) }
        }
        let activeTerminalSessionIDs = Set(activeLeaves.compactMap(\.1.terminalSessionID))
        let activeBrowserSessionIDs = Set(activeLeaves.compactMap(\.1.browserSessionID))
        sessions.removeSessions(notIn: activeTerminalSessionIDs)
        browserSessions.removeSessions(notIn: activeBrowserSessionIDs)
        paneControllers.removeControllers(notIn: Set(activeLeaves.map(\.1.id)))
        browserPaneControllers.removeControllers(notIn: Set(activeLeaves.map(\.1.id)))
        reconcileTerminalSessionObservations()
    }
}
