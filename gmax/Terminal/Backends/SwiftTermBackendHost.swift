//
//  SwiftTermBackendHost.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import Foundation

@MainActor
final class SwiftTermBackendHost: TerminalBackendHost {
    let controller: TerminalPaneController

    var paneID: PaneID { controller.paneID }
    var session: TerminalSession { controller.session }
    let kind: TerminalBackendKind = .swiftTerm
    let capabilities: TerminalBackendCapabilities = .swiftTerm

    init(paneID: PaneID, session: TerminalSession) {
        controller = TerminalPaneController(paneID: paneID, session: session)
    }

    func captureHistory() -> WorkspaceSessionHistorySnapshot? {
        controller.captureHistory()
    }
}
