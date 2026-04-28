//
//  TerminalBackendRegistry.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import Foundation
import OSLog

@MainActor
final class TerminalBackendRegistry {
    private var hostsBySessionID: [TerminalSessionID: any TerminalBackendHost] = [:]

    func host(for pane: PaneLeaf, session: TerminalSession) -> any TerminalBackendHost {
        if let host = hostsBySessionID[session.id] {
            return host
        }

        let kind = pane.resolvedTerminalBackendKind
        let host: any TerminalBackendHost = switch kind {
            case .swiftTerm:
                SwiftTermBackendHost(paneID: pane.id, session: session)
            case .ghostty:
                GhosttyBackendHost(paneID: pane.id, session: session)
        }
        hostsBySessionID[session.id] = host

        Logger.pane.notice("Created a terminal backend host for a pane session. Backend: \(kind.rawValue, privacy: .public). Pane ID: \(pane.id.rawValue.uuidString, privacy: .public). Session ID: \(session.id.rawValue.uuidString, privacy: .public)")
        return host
    }

    func existingHost(for sessionID: TerminalSessionID) -> (any TerminalBackendHost)? {
        hostsBySessionID[sessionID]
    }

    func removeHosts(notIn retainedSessionIDs: Set<TerminalSessionID>) {
        hostsBySessionID = hostsBySessionID.filter { retainedSessionIDs.contains($0.key) }
    }
}
