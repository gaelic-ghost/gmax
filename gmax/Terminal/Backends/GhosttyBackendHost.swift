//
//  GhosttyBackendHost.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import AppKit
import Foundation

@MainActor
final class GhosttyBackendHost: TerminalBackendHost {
    let paneID: PaneID
    let session: TerminalSession
    let kind: TerminalBackendKind = .ghostty
    let capabilities: TerminalBackendCapabilities = .ghosttySpike

    private var retainedHostView: GhosttyPaneHostView?
    private var retainedGeneration: Int?

    init(paneID: PaneID, session: TerminalSession) {
        self.paneID = paneID
        self.session = session
    }

    func hostView(onClose: @escaping () -> Void) -> GhosttyPaneHostView {
        if
            let retainedHostView,
            retainedGeneration == session.relaunchGeneration {
            retainedHostView.onCloseRequested = onClose
            retainedHostView.removeFromSuperview()
            return retainedHostView
        }

        let hostView = GhosttyPaneHostView(session: session)
        hostView.onCloseRequested = onClose
        retainedHostView = hostView
        retainedGeneration = session.relaunchGeneration
        return hostView
    }

    func update(hostView: GhosttyPaneHostView, onClose: @escaping () -> Void) {
        guard retainedHostView === hostView else {
            return
        }

        hostView.onCloseRequested = onClose
        hostView.refreshSurface()
    }

    func detach(hostView: GhosttyPaneHostView) {
        guard retainedHostView === hostView else {
            return
        }

        hostView.onCloseRequested = nil
    }

    func captureHistory() -> WorkspaceSessionHistorySnapshot? {
        nil
    }
}
