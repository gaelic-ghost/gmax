//
//  TerminalBackend.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import Foundation

enum TerminalBackendKind: String, Codable, Hashable {
    case swiftTerm
    case ghostty

    static var selectedForNewSession: TerminalBackendKind {
        GhosttyPaneSpikeSwitch.isEnabled ? .ghostty : .swiftTerm
    }
}

struct TerminalBackendCapabilities: Hashable {
    static let swiftTerm = TerminalBackendCapabilities(
        title: true,
        currentDirectory: true,
        shellPhase: true,
        lastCommandExitStatus: true,
        bell: true,
        notification: true,
        copyPaste: true,
        selection: true,
        search: true,
        historyTextExport: true,
        historyRestore: true,
        closeRequest: true,
        readableAccessibilityText: true,
    )

    static let ghosttySpike = TerminalBackendCapabilities(
        title: true,
        currentDirectory: true,
        shellPhase: true,
        lastCommandExitStatus: true,
        bell: false,
        notification: true,
        copyPaste: false,
        selection: false,
        search: false,
        historyTextExport: false,
        historyRestore: false,
        closeRequest: true,
        readableAccessibilityText: false,
    )

    var title: Bool
    var currentDirectory: Bool
    var shellPhase: Bool
    var lastCommandExitStatus: Bool
    var bell: Bool
    var notification: Bool
    var copyPaste: Bool
    var selection: Bool
    var search: Bool
    var historyTextExport: Bool
    var historyRestore: Bool
    var closeRequest: Bool
    var readableAccessibilityText: Bool
}

@MainActor
protocol TerminalBackendHost: AnyObject {
    var paneID: PaneID { get }
    var session: TerminalSession { get }
    var kind: TerminalBackendKind { get }
    var capabilities: TerminalBackendCapabilities { get }

    func captureHistory() -> WorkspaceSessionHistorySnapshot?
}
