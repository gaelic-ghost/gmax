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

	var body: some View {
		let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let state = switch session.state {
			case .idle: "Shell ready to launch"
			case .running: "Shell running"
			case .exited(let exitCode): exitCode.map { "Shell exited with status \($0)" } ?? "Shell exited"
		}
		let accessibilityLabel = title.isEmpty || title == "Shell" ? "Shell pane" : "\(title) pane"
		let accessibilityValue = [
			isFocused ? "Focused" : nil,
			state,
			session.currentDirectory.flatMap { $0.isEmpty ? nil : "Directory \($0)" }
		].compactMap(\.self).joined(separator: ". ")
		ZStack(alignment: .topLeading) {
			TerminalPaneView(
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
			.id("\(pane.id.rawValue.uuidString)-\(session.relaunchGeneration)")
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
		.background(isFocused ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.35)))
		.contentShape(Rectangle())
		.focusedValue(\.closeFocusedPane, isFocused ? onClose : nil)
		.onTapGesture(perform: onFocus)
		.accessibilityElement(children: .contain)
		.accessibilityLabel(accessibilityLabel)
		.accessibilityValue(accessibilityValue)
		.accessibilityHint("Activate to focus this pane. Additional actions are available for splitting, closing, and restarting the shell.")
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
