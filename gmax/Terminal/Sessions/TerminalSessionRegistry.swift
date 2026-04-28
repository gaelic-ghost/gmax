//
//  TerminalSessionRegistry.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation

@MainActor
final class TerminalSessionRegistry {
    private let defaultLaunchConfiguration: TerminalLaunchConfiguration
    private var sessionsByID: [TerminalSessionID: TerminalSession]

    init(
        workspaces: [Workspace],
        defaultLaunchConfiguration: TerminalLaunchConfiguration = .loginShell,
        restoredPaneSnapshotsBySessionID: [TerminalSessionID: WorkspaceSessionSnapshot] = [:],
    ) {
        self.defaultLaunchConfiguration = defaultLaunchConfiguration
        sessionsByID = [:]
        for workspace in workspaces {
            for leaf in workspace.root?.leaves() ?? [] {
                guard let sessionID = leaf.terminalSessionID else {
                    continue
                }

                let paneSnapshot = restoredPaneSnapshotsBySessionID[sessionID]
                let launchConfiguration = (paneSnapshot?.launchConfiguration ?? defaultLaunchConfiguration)
                    .normalizingCurrentDirectory()
                sessionsByID[sessionID] = TerminalSession(
                    id: sessionID,
                    launchConfiguration: launchConfiguration,
                    title: paneSnapshot?.title ?? "Shell",
                    currentDirectory: launchConfiguration.currentDirectory,
                )
                sessionsByID[sessionID]?.setRestoredHistory(paneSnapshot?.history)
            }
        }
    }

    func ensureSession(
        id: TerminalSessionID,
        launchConfiguration: TerminalLaunchConfiguration? = nil,
    ) -> TerminalSession {
        if let session = sessionsByID[id] {
            return session
        }

        let resolvedLaunchConfiguration = (launchConfiguration ?? defaultLaunchConfiguration)
            .normalizingCurrentDirectory()
        let session = TerminalSession(
            id: id,
            launchConfiguration: resolvedLaunchConfiguration,
            currentDirectory: resolvedLaunchConfiguration.currentDirectory,
        )
        sessionsByID[id] = session
        return session
    }

    func session(for id: TerminalSessionID) -> TerminalSession? {
        sessionsByID[id]
    }

    func allSessions() -> [TerminalSession] {
        Array(sessionsByID.values)
    }

    func removeSessions(notIn retainedSessionIDs: Set<TerminalSessionID>) {
        sessionsByID = sessionsByID.filter { retainedSessionIDs.contains($0.key) }
    }
}
