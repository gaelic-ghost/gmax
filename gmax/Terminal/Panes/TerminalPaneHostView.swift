//
//  TerminalPaneHostView.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import AppKit
import SwiftTerm

struct TerminalAccessibilitySnapshot {
    let label: String
    let value: String
    let help: String
}

final class TerminalPaneHostView: NSView {
    let terminalView: LocalProcessTerminalView
    var onEffectiveAppearanceChange: ((NSAppearance) -> Void)?

    private var accessibilitySnapshot = TerminalAccessibilitySnapshot(label: "Shell terminal", value: "", help: "")
    private var onAccessibilityRestart: (() -> Void)?
    private var onAccessibilitySplitRight: (() -> Void)?
    private var onAccessibilitySplitDown: (() -> Void)?
    private var onAccessibilityClose: (() -> Void)?

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onEffectiveAppearanceChange?(effectiveAppearance)
    }

    func updateAccessibility(
        snapshot: TerminalAccessibilitySnapshot,
        onRestart: @escaping () -> Void,
        onSplitRight: @escaping () -> Void,
        onSplitDown: @escaping () -> Void,
        onClose: @escaping () -> Void,
    ) {
        accessibilitySnapshot = snapshot
        onAccessibilityRestart = onRestart
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
        terminalView.setAccessibilityLabel(snapshot.label)
        terminalView.setAccessibilityHelp(snapshot.help)
        terminalView.setAccessibilityCustomActions(customActions)
    }

    private func setup() {
        wantsLayer = true
        if terminalView.superview !== self {
            terminalView.removeFromSuperview()
        }
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminalView)

        NSLayoutConstraint.activate([
            terminalView.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: trailingAnchor),
            terminalView.topAnchor.constraint(equalTo: topAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func makeAccessibilityCustomActions() -> [NSAccessibilityCustomAction] {
        [
            NSAccessibilityCustomAction(name: "Restart Shell", target: self, selector: #selector(accessibilityRestartShell)),
            NSAccessibilityCustomAction(name: "Split Right", target: self, selector: #selector(accessibilitySplitRight)),
            NSAccessibilityCustomAction(name: "Split Down", target: self, selector: #selector(accessibilitySplitDown)),
            NSAccessibilityCustomAction(name: "Close Pane", target: self, selector: #selector(accessibilityClosePane)),
        ]
    }

    @objc
    private func accessibilityRestartShell() -> Bool {
        onAccessibilityRestart?()
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
