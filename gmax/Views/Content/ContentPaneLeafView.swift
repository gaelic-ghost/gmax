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
	let isFocused: Bool
	let onFocus: () -> Void
	let onSplitRight: () -> Void
	let onSplitDown: () -> Void
	let onClose: () -> Void

	private var terminalHostIdentity: String {
		"\(pane.id.rawValue.uuidString)-\(session.relaunchGeneration)"
	}

	var body: some View {
		ZStack(alignment: .topLeading) {
			TerminalPaneRepresentable(
				controller: controller,
				session: session,
				isFocused: isFocused,
				onFocus: onFocus,
				onRestart: restartShell,
				onSplitRight: onSplitRight,
				onSplitDown: onSplitDown,
				onClose: onClose
			)
			// The pane host must stay keyed to the actual pane leaf, not just relaunches,
			// or SwiftUI can reuse a surviving sibling's coordinator after split collapse.
			.id(terminalHostIdentity)
			.background(.black)

			if case .exited(let exitCode) = session.state {
				exitedSessionOverlay(exitCode: exitCode)
			}

			VStack(alignment: .leading, spacing: 10) {
				HStack(spacing: 8) {
					Text(session.title)
						.font(.headline)
						.lineLimit(1)
					if let currentDirectory = session.currentDirectory {
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
			.padding(12)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.focusable(interactions: .activate)
		.background {
			GeometryReader { geometry in
				Color.clear.preference(
					key: ContentPaneFramePreferenceKey.self,
					value: [pane.id: geometry.frame(in: .named("workspace-pane-tree"))]
				)
			}
		}
		.background(backgroundStyle)
		.contentShape(Rectangle())
		.focusedValue(\.closeFocusedPaneAction, isFocused ? onClose : nil)
		.onTapGesture(perform: onFocus)
		.accessibilityElement(children: .contain)
		.accessibilityLabel(accessibilityLabel)
		.accessibilityValue(accessibilityValue)
		.accessibilityHint(accessibilityHint)
		.accessibilityRespondsToUserInteraction(true)
		.accessibilityAddTraits(isFocused ? .isSelected : [])
		.accessibilityAction(.default) {
			onFocus()
		}
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

	@ViewBuilder
	private func exitedSessionOverlay(exitCode: Int32?) -> some View {
		VStack(spacing: 10) {
			Text("Shell Session Ended")
				.font(.headline.weight(.semibold))

			Text(exitDescription(exitCode: exitCode))
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

	private func exitDescription(exitCode: Int32?) -> String {
		if let exitCode {
			return "The shell process exited with status \(exitCode). Start a fresh login shell in this pane when you're ready."
		}

		return "The shell process ended unexpectedly or without a reported exit status. Start a fresh login shell in this pane when you're ready."
	}

	private var backgroundStyle: some ShapeStyle {
		if isFocused {
			return AnyShapeStyle(.tint.opacity(0.18))
		}
		return AnyShapeStyle(.quaternary.opacity(0.35))
	}

	private var accessibilityLabel: String {
		let trimmedTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
		if trimmedTitle.isEmpty || trimmedTitle == "Shell" {
			return "Shell pane"
		}
		return "\(trimmedTitle) pane"
	}

	private var accessibilityValue: String {
		var details: [String] = []
		if isFocused {
			details.append("Focused")
		}
		details.append(stateAccessibilityValue)
		if let currentDirectory = session.currentDirectory, !currentDirectory.isEmpty {
			details.append("Directory \(currentDirectory)")
		}
		return details.joined(separator: ". ")
	}

	private var accessibilityHint: String {
		"Activate to focus this pane. Additional actions are available for splitting, closing, and restarting the shell."
	}

	private func restartShell() {
		guard session.state != .running else {
			return
		}
		controller.session.prepareForRelaunch()
	}

	private var stateAccessibilityValue: String {
		switch session.state {
			case .idle:
				return "Shell ready to launch"
			case .running:
				return "Shell running"
			case .exited(let exitCode):
				if let exitCode {
					return "Shell exited with status \(exitCode)"
				}
				return "Shell exited"
		}
	}
}
