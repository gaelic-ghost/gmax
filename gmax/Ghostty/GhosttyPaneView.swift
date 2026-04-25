//
//  GhosttyPaneView.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import SwiftUI

struct GhosttyPaneView: NSViewRepresentable {
    let backendHost: GhosttyBackendHost
    let onClose: () -> Void

    static func dismantleNSView(_ nsView: GhosttyPaneHostView, coordinator: Coordinator) {
        coordinator.dismantle(hostView: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(backendHost: backendHost)
    }

    func makeNSView(context: Context) -> GhosttyPaneHostView {
        backendHost.hostView(onClose: onClose)
    }

    func updateNSView(_ nsView: GhosttyPaneHostView, context: Context) {
        backendHost.update(hostView: nsView, onClose: onClose)
    }

    final class Coordinator {
        let backendHost: GhosttyBackendHost

        init(backendHost: GhosttyBackendHost) {
            self.backendHost = backendHost
        }

        func dismantle(hostView: GhosttyPaneHostView) {
            backendHost.detach(hostView: hostView)
        }
    }
}
