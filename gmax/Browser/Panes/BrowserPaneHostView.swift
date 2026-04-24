//
//  BrowserPaneHostView.swift
//  gmax
//
//  Created by Codex on 4/24/26.
//

import AppKit
import WebKit

struct BrowserAccessibilitySnapshot {
    let label: String
    let value: String
    let help: String
}

final class BrowserPaneHostView: NSView {
    let webView: WKWebView

    private var accessibilitySnapshot = BrowserAccessibilitySnapshot(label: "Browser pane", value: "", help: "")
    private var onAccessibilityReload: (() -> Void)?
    private var onAccessibilitySplitRight: (() -> Void)?
    private var onAccessibilitySplitDown: (() -> Void)?
    private var onAccessibilityClose: (() -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateAccessibility(
        snapshot: BrowserAccessibilitySnapshot,
        onReload: @escaping () -> Void,
        onSplitRight: @escaping () -> Void,
        onSplitDown: @escaping () -> Void,
        onClose: @escaping () -> Void,
    ) {
        accessibilitySnapshot = snapshot
        onAccessibilityReload = onReload
        onAccessibilitySplitRight = onSplitRight
        onAccessibilitySplitDown = onSplitDown
        onAccessibilityClose = onClose

        setAccessibilityElement(true)
        setAccessibilityEnabled(true)
        setAccessibilityLabel(snapshot.label)
        setAccessibilityValue(snapshot.value)
        setAccessibilityHelp(snapshot.help)

        let customActions = makeAccessibilityCustomActions()
        setAccessibilityCustomActions(customActions)
        webView.setAccessibilityLabel(snapshot.label)
        webView.setAccessibilityHelp(snapshot.help)
        webView.setAccessibilityCustomActions(customActions)
    }

    private func setup() {
        wantsLayer = true
        if webView.superview !== self {
            webView.removeFromSuperview()
        }
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeAccessibilityCustomActions() -> [NSAccessibilityCustomAction] {
        [
            NSAccessibilityCustomAction(name: "Reload Page", target: self, selector: #selector(accessibilityReload)),
            NSAccessibilityCustomAction(name: "Split Right", target: self, selector: #selector(accessibilitySplitRight)),
            NSAccessibilityCustomAction(name: "Split Down", target: self, selector: #selector(accessibilitySplitDown)),
            NSAccessibilityCustomAction(name: "Close Pane", target: self, selector: #selector(accessibilityClosePane)),
        ]
    }

    @objc
    private func accessibilityReload() -> Bool {
        onAccessibilityReload?()
        return true
    }

    @objc
    private func accessibilitySplitRight() -> Bool {
        onAccessibilitySplitRight?()
        return true
    }

    @objc
    private func accessibilitySplitDown() -> Bool {
        onAccessibilitySplitDown?()
        return true
    }

    @objc
    private func accessibilityClosePane() -> Bool {
        onAccessibilityClose?()
        return true
    }
}
