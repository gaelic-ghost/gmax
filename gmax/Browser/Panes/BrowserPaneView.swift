//
//  BrowserPaneView.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import AppKit
import SwiftUI

struct BrowserPaneView: NSViewRepresentable {
    @Environment(\.openURL) private var openURL

    let controller: BrowserPaneController
    let session: BrowserSession
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClose: () -> Void

    private var accessibilitySnapshot: BrowserAccessibilitySnapshot {
        let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = if trimmedTitle.isEmpty || trimmedTitle == "Browser" {
            "Browser pane"
        } else {
            "\(trimmedTitle) browser pane"
        }

        var valueParts: [String] = []
        switch session.state {
            case .idle:
                valueParts.append("Browser ready")
            case .loading:
                valueParts.append("Browser loading")
            case let .failed(message):
                valueParts.append(message)
        }
        if let currentURL = session.url, !currentURL.isEmpty {
            valueParts.append("URL \(currentURL)")
        } else if let lastCommittedURL = session.lastCommittedURL, !lastCommittedURL.isEmpty {
            valueParts.append("Last committed URL \(lastCommittedURL)")
        }

        return BrowserAccessibilitySnapshot(
            label: label,
            value: valueParts.joined(separator: ". "),
            help: "This browser lives inside a workspace pane. Use the available accessibility actions to reload, split, or close the pane.",
        )
    }

    static func dismantleNSView(_ nsView: BrowserPaneHostView, coordinator: Coordinator) {
        coordinator.dismantle(hostingView: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            controller: controller,
            openExternalURL: { url in
                openURL(url)
            },
        )
    }

    func makeNSView(context: Context) -> BrowserPaneHostView {
        let hostingView = context.coordinator.makeHostingView()
        hostingView.updateAccessibility(
            snapshot: accessibilitySnapshot,
            onReload: controller.reload,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClose: onClose,
        )
        return hostingView
    }

    func updateNSView(_ nsView: BrowserPaneHostView, context: Context) {
        context.coordinator.update(hostingView: nsView)
        nsView.updateAccessibility(
            snapshot: accessibilitySnapshot,
            onReload: controller.reload,
            onSplitRight: onSplitRight,
            onSplitDown: onSplitDown,
            onClose: onClose,
        )
    }
}
