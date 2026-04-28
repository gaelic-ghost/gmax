//
//  GhosttyBackendHost.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import AppKit
import Combine
import Foundation

enum GhosttyBackendLifecycleState: Equatable {
    case unloaded
    case loading
    case ready
    case failed(String)
    case closed

    var failureMessage: String? {
        switch self {
            case let .failed(message):
                message
            default:
                nil
        }
    }
}

@MainActor
final class GhosttyBackendHost: ObservableObject, TerminalBackendHost {
    let paneID: PaneID
    let session: TerminalSession
    let kind: TerminalBackendKind = .ghostty
    let capabilities: TerminalBackendCapabilities = .ghosttySpike

    @Published private(set) var lifecycleState: GhosttyBackendLifecycleState = .unloaded

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
            retainedHostView.onLifecycleStateChange = { [weak self] state in
                self?.updateLifecycleState(state)
            }
            retainedHostView.removeFromSuperview()
            return retainedHostView
        }

        updateLifecycleState(.loading)
        let hostView = GhosttyPaneHostView(session: session)
        hostView.onCloseRequested = onClose
        hostView.onLifecycleStateChange = { [weak self] state in
            self?.updateLifecycleState(state)
        }
        retainedHostView = hostView
        retainedGeneration = session.relaunchGeneration
        return hostView
    }

    func update(hostView: GhosttyPaneHostView, onClose: @escaping () -> Void) {
        guard retainedHostView === hostView else {
            return
        }

        hostView.onCloseRequested = onClose
        hostView.onLifecycleStateChange = { [weak self] state in
            self?.updateLifecycleState(state)
        }
        hostView.refreshSurface()
    }

    func detach(hostView: GhosttyPaneHostView) {
        guard retainedHostView === hostView else {
            return
        }

        hostView.onCloseRequested = nil
        hostView.onLifecycleStateChange = nil
    }

    func captureHistory() -> WorkspaceSessionHistorySnapshot? {
        nil
    }

    private func updateLifecycleState(_ state: GhosttyBackendLifecycleState) {
        lifecycleState = state
    }
}
