//
//  WorkspacePaneTreeView.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import SwiftUI

struct WorkspacePaneTreeView: View {
	let workspace: Workspace
	let controllerForPane: (PaneLeaf) -> TerminalPaneController
	let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
	let onUpdatePaneFrames: ([PaneID: CGRect]) -> Void
	let onFocusPane: (PaneID) -> Void
	let onSplitPane: (PaneID, SplitDirection) -> Void
	let onClosePane: (PaneID) -> Void

	var body: some View {
		Group {
			if let root = workspace.root {
				PaneNodeView(
					node: root,
					focusedPaneID: workspace.focusedPaneID,
					workspaceID: workspace.id,
					controllerForPane: controllerForPane,
					onUpdateSplitFraction: onUpdateSplitFraction,
					onFocusPane: onFocusPane,
					onSplitPane: onSplitPane,
					onClosePane: onClosePane
				)
			}
		}
		.coordinateSpace(name: "workspace-pane-tree")
		.focusSection()
		.accessibilityElement(children: .contain)
		.accessibilityLabel("Workspace pane area")
		.onPreferenceChange(PaneFramePreferenceKey.self, perform: onUpdatePaneFrames)
	}
}

private struct PaneNodeView: View {
	let node: PaneNode
	let focusedPaneID: PaneID?
	let workspaceID: WorkspaceID
	let controllerForPane: (PaneLeaf) -> TerminalPaneController
	let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
	let onFocusPane: (PaneID) -> Void
	let onSplitPane: (PaneID, SplitDirection) -> Void
	let onClosePane: (PaneID) -> Void

	var body: some View {
		switch node {
			case .leaf(let leaf):
				let controller = controllerForPane(leaf)
				PaneLeafCard(
					pane: leaf,
					controller: controller,
					session: controller.session,
					isFocused: leaf.id == focusedPaneID,
					onFocus: { onFocusPane(leaf.id) },
					onSplitRight: {
						onSplitPane(leaf.id, .right)
					},
					onSplitDown: {
						onSplitPane(leaf.id, .down)
					},
					onClose: {
						onClosePane(leaf.id)
					}
				)

			case .split(let split):
				PaneSplitContainer(
					axis: split.axis,
					fraction: split.fraction,
					onFractionChange: { onUpdateSplitFraction(split.id, $0) }
				) {
					PaneNodeView(
						node: split.first,
						focusedPaneID: focusedPaneID,
						workspaceID: workspaceID,
						controllerForPane: controllerForPane,
						onUpdateSplitFraction: onUpdateSplitFraction,
						onFocusPane: onFocusPane,
						onSplitPane: onSplitPane,
						onClosePane: onClosePane
					)
				} second: {
					PaneNodeView(
						node: split.second,
						focusedPaneID: focusedPaneID,
						workspaceID: workspaceID,
						controllerForPane: controllerForPane,
						onUpdateSplitFraction: onUpdateSplitFraction,
						onFocusPane: onFocusPane,
						onSplitPane: onSplitPane,
						onClosePane: onClosePane
					)
				}
		}
	}
}

private struct PaneSplitContainer<First: View, Second: View>: View {
	private let axis: PaneSplit.Axis
	private let fraction: CGFloat
	private let onFractionChange: (CGFloat) -> Void
	private let first: First
	private let second: Second
	private let dividerThickness: CGFloat = 10
	private let minimumPaneLength: CGFloat = 160

	init(
		axis: PaneSplit.Axis,
		fraction: CGFloat,
		onFractionChange: @escaping (CGFloat) -> Void,
		@ViewBuilder first: () -> First,
		@ViewBuilder second: () -> Second
	) {
		self.axis = axis
		self.fraction = fraction
		self.onFractionChange = onFractionChange
		self.first = first()
		self.second = second()
	}

	var body: some View {
		GeometryReader { geometry in
			let primaryLength = axis == .horizontal ? geometry.size.width : geometry.size.height
			let clampedFraction = clampedFraction(for: primaryLength)
			let availableLength = max(primaryLength - dividerThickness, 0)
			let firstLength = availableLength * clampedFraction
			let secondLength = max(availableLength - firstLength, 0)

			ZStack {
				if axis == .horizontal {
					HStack(spacing: 0) {
						first
							.frame(width: firstLength)
							.frame(maxHeight: .infinity)
						divider(for: geometry.size)
						second
							.frame(width: secondLength)
							.frame(maxHeight: .infinity)
					}
				} else {
					VStack(spacing: 0) {
						first
							.frame(height: firstLength)
							.frame(maxWidth: .infinity)
						divider(for: geometry.size)
						second
							.frame(height: secondLength)
							.frame(maxWidth: .infinity)
					}
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
	}

	private func divider(for size: CGSize) -> some View {
		let totalLength = axis == .horizontal ? size.width : size.height
		let currentFraction = clampedFraction(for: totalLength)

		return Rectangle()
			.fill(.separator.opacity(0.9))
			.overlay {
				Rectangle()
					.fill(.quaternary.opacity(0.45))
					.padding(axis == .horizontal ? .vertical : .horizontal, 2)
			}
			.frame(
				width: axis == .horizontal ? dividerThickness : nil,
				height: axis == .vertical ? dividerThickness : nil
			)
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 0)
					.onChanged { value in
						let totalLength = axis == .horizontal ? size.width : size.height
						guard totalLength > dividerThickness else {
							return
						}

						let dragLocation = axis == .horizontal ? value.location.x : value.location.y
						let proposedFraction = (dragLocation - (dividerThickness / 2)) / max(totalLength - dividerThickness, 1)
						onFractionChange(clamped(proposedFraction, for: totalLength))
					}
			)
			.onHover { isHovering in
				if isHovering {
					if axis == .horizontal {
						NSCursor.resizeLeftRight.set()
					} else {
						NSCursor.resizeUpDown.set()
					}
				} else {
					NSCursor.arrow.set()
				}
			}
			.accessibilityElement()
			.accessibilityLabel(dividerAccessibilityLabel)
			.accessibilityValue("\(Int(currentFraction * 100)) percent")
			.accessibilityHint("Adjust to resize the panes on either side of this divider.")
			.accessibilityAdjustableAction { direction in
				let step: CGFloat = 0.05
				switch direction {
					case .increment:
						onFractionChange(clamped(currentFraction + step, for: totalLength))
					case .decrement:
						onFractionChange(clamped(currentFraction - step, for: totalLength))
					@unknown default:
						break
				}
			}
	}

	private func clampedFraction(for totalLength: CGFloat) -> CGFloat {
		clamped(fraction, for: totalLength)
	}

	private func clamped(_ proposedFraction: CGFloat, for totalLength: CGFloat) -> CGFloat {
		let usableLength = max(totalLength - dividerThickness, 0)
		guard usableLength > 0 else {
			return 0.5
		}

		let minimumFraction = min(minimumPaneLength / usableLength, 0.5)
		let maximumFraction = max(1 - minimumFraction, 0.5)
		return min(max(proposedFraction, minimumFraction), maximumFraction)
	}

	private var dividerAccessibilityLabel: String {
		switch axis {
			case .horizontal:
				return "Vertical pane divider"
			case .vertical:
				return "Horizontal pane divider"
		}
	}
}

private struct PaneLeafCard: View {
	let pane: PaneLeaf
	let controller: TerminalPaneController
	@ObservedObject var session: TerminalSession
	let isFocused: Bool
	let onFocus: () -> Void
	let onSplitRight: () -> Void
	let onSplitDown: () -> Void
	let onClose: () -> Void

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
			.id(session.relaunchGeneration)
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
					key: PaneFramePreferenceKey.self,
					value: [pane.id: geometry.frame(in: .named("workspace-pane-tree"))]
				)
			}
		}
		.background(backgroundStyle)
		.contentShape(Rectangle())
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

private struct PaneFramePreferenceKey: PreferenceKey {
	static var defaultValue: [PaneID: CGRect] = [:]

	static func reduce(value: inout [PaneID: CGRect], nextValue: () -> [PaneID: CGRect]) {
		value.merge(nextValue(), uniquingKeysWith: { _, new in new })
	}
}
