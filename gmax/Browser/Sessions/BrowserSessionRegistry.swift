//
//  BrowserSessionRegistry.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import Foundation

@MainActor
final class BrowserSessionRegistry {
    private var sessionsByID: [BrowserSessionID: BrowserSession]

    init(
        workspaces: [Workspace],
        restoredSnapshotsBySessionID: [BrowserSessionID: BrowserSessionSnapshot] = [:],
    ) {
        sessionsByID = [:]
        for workspace in workspaces {
            for leaf in workspace.root?.leaves() ?? [] {
                guard let sessionID = leaf.browserSessionID else {
                    continue
                }

                let session = restoredSnapshotsBySessionID[sessionID].map(BrowserSession.init(snapshot:))
                    ?? BrowserSession(id: sessionID)
                sessionsByID[sessionID] = session
            }
        }
    }

    func ensureSession(id: BrowserSessionID) -> BrowserSession {
        if let session = sessionsByID[id] {
            return session
        }

        let session = BrowserSession(id: id)
        sessionsByID[id] = session
        return session
    }

    func ensureSession(id: BrowserSessionID, snapshot: BrowserSessionSnapshot) -> BrowserSession {
        if let session = sessionsByID[id] {
            return session
        }

        let session = BrowserSession(snapshot: snapshot)
        sessionsByID[id] = session
        return session
    }

    func session(for id: BrowserSessionID) -> BrowserSession? {
        sessionsByID[id]
    }

    func removeSessions(notIn retainedSessionIDs: Set<BrowserSessionID>) {
        sessionsByID = sessionsByID.filter { retainedSessionIDs.contains($0.key) }
    }
}
