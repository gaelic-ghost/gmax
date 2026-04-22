//
//  ContentPaneLeafView.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import SwiftUI

struct ContentPaneLeafView: View {
    let pane: PaneLeaf
    let controller: TerminalPaneController
    @ObservedObject var session: TerminalSession

    let focusedTarget: FocusState<WorkspaceFocusTarget?>.Binding
    let onMovePaneFocus: (PaneFocusDirection) -> Void
    let onSplitRight: () -> Void
    let onSplitDown: () -> Void
    let onClose: () -> Void

    var body: some View {
        let isFocused = focusedTarget.wrappedValue == .pane(pane.id)
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let state = switch session.state {
            case .idle: "Shell ready to launch"
            case .running: "Shell running"
            case let .exited(exitCode): exitCode.map { "Shell exited with status \($0)" } ?? "Shell exited"
        }
        let paneHostIdentity = "\(pane.id.rawValue.uuidString)-\(session.relaunchGeneration)"
        let accessibilityLabel = title.isEmpty || title == "Shell" ? "Shell pane" : "\(title) pane"
        let accessibilityValue = [
            isFocused ? "Focused" : nil,
            state,
            session.currentDirectory.flatMap { $0.isEmpty ? nil : "Directory \($0)" },
        ]
        .compactMap(\.self)
        .joined(separator: ". ")
        let splitFocusedPane: (SplitDirection) -> Void = { direction in
            switch direction {
                case .right:
                    onSplitRight()
                case .down:
                    onSplitDown()
            }
        }
        let paneActionsHint = "Activate to focus this pane. Additional actions are available for splitting, closing, and restarting the shell."
        let focusBackgroundStyle = isFocused ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.35))
        paneSurface(isFocused: isFocused, paneHostIdentity: paneHostIdentity)
			.focusable(interactions: .edit)
            .focused(focusedTarget, equals: .pane(pane.id))
            .background(ContentPaneFrameReporter(paneID: pane.id))
            .background(focusBackgroundStyle)
            .contentShape(Rectangle())
            .focusedValue(\.moveFocusedPaneFocus, onMovePaneFocus)
            .focusedValue(\.splitFocusedPane, splitFocusedPane)
            .focusedValue(\.closeFocusedPane, onClose)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(accessibilityValue)
            .accessibilityHint(paneActionsHint)
            .accessibilityIdentifier("contentPane.leaf.\(pane.id.rawValue.uuidString)")
            .accessibilityRespondsToUserInteraction(true)
            .accessibilityAddTraits(isFocused ? .isSelected : [])
            .accessibilityAction(named: Text("Split Right")) {
                onSplitRight()
            }
            .accessibilityAction(named: Text("Split Down")) {
                onSplitDown()
            }
            .accessibilityAction(named: Text("Close Pane")) {
                onClose()
            }
            .accessibilityAction(named: Text("Restart Shell")) {
                restartShell()
            }
    }

    private func paneSurface(isFocused: Bool, paneHostIdentity: String) -> some View {
        ZStack(alignment: .topLeading) {
            TerminalPaneView(
                controller: controller,
                session: session,
                onRestart: restartShell,
                onSplitRight: onSplitRight,
                onSplitDown: onSplitDown,
                onClose: onClose,
            )
            // The pane host must stay keyed to the actual pane leaf, not just relaunches,
            // or SwiftUI can reuse a surviving sibling's coordinator after split collapse.
            .id(paneHostIdentity)
            .background(.black)

            if case let .exited(exitCode) = session.state {
                exitedSessionOverlay(exitCode: exitCode)
            }

            ContentPaneLeafHeader(
                title: session.title,
                currentDirectory: session.currentDirectory,
                isFocused: isFocused,
            )
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exitedSessionOverlay(exitCode: Int32?) -> some View {
        VStack(spacing: 10) {
            Text("Shell Session Ended")
                .font(.headline.weight(.semibold))

            Text(exitCode.map {
                "The shell process exited with status \($0). Start a fresh login shell in this pane when you're ready."
            } ?? "The shell process ended unexpectedly or without a reported exit status. Start a fresh login shell in this pane when you're ready.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Restart Shell") {
                restartShell()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func restartShell() {
        guard session.state != .running else { return }

        session.prepareForRelaunch()
    }
}

private struct ContentPaneLeafHeader: View {
    let title: String
    let currentDirectory: String?
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                if let currentDirectory {
                    Text(currentDirectory)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if isFocused {
                    Text("Focused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ContentPaneFrameReporter: View {
    let paneID: PaneID

    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: ContentPaneFramePreferenceKey.self,
                value: [paneID: geometry.frame(in: .named("workspace-pane-tree"))],
            )
        }
    }
}
