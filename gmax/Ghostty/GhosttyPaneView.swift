//
//  GhosttyPaneView.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import SwiftUI

struct GhosttyPaneView: NSViewRepresentable {
    let session: TerminalSession
    let onClose: () -> Void

    static func dismantleNSView(_ nsView: GhosttyPaneHostView, coordinator: Coordinator) {
        coordinator.dismantle(hostView: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GhosttyPaneHostView {
        let hostView = GhosttyPaneHostView(session: session)
        hostView.onCloseRequested = onClose
        return hostView
    }

    func updateNSView(_ nsView: GhosttyPaneHostView, context: Context) {
        nsView.onCloseRequested = onClose
        nsView.refreshSurface()
    }

    final class Coordinator {
        func dismantle(hostView: GhosttyPaneHostView) {
            hostView.onCloseRequested = nil
        }
    }
}
