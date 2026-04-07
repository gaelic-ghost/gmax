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

	var body: some View {
		Group {
			if let root = workspace.root {
				PaneNodeView(
					node: root,
					focusedPaneID: workspace.focusedPaneID,
						controllerForPane: controllerForPane,
						onUpdateSplitFraction: onUpdateSplitFraction,
						onFocusPane: onFocusPane
					)
				}
			}
			.coordinateSpace(name: "workspace-pane-tree")
		.onPreferenceChange(PaneFramePreferenceKey.self, perform: onUpdatePaneFrames)
	}
}

private struct PaneNodeView: View {
	let node: PaneNode
	let focusedPaneID: PaneID?
	let controllerForPane: (PaneLeaf) -> TerminalPaneController
	let onUpdateSplitFraction: (SplitID, CGFloat) -> Void
	let onFocusPane: (PaneID) -> Void

	var body: some View {
		switch node {
			case .leaf(let leaf):
				let controller = controllerForPane(leaf)
				PaneLeafCard(
					pane: leaf,
						controller: controller,
						session: controller.session,
						isFocused: leaf.id == focusedPaneID,
						onFocus: { onFocusPane(leaf.id) }
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
							controllerForPane: controllerForPane,
							onUpdateSplitFraction: onUpdateSplitFraction,
							onFocusPane: onFocusPane
						)
					} second: {
						PaneNodeView(
						node: split.second,
						focusedPaneID: focusedPaneID,
							controllerForPane: controllerForPane,
							onUpdateSplitFraction: onUpdateSplitFraction,
							onFocusPane: onFocusPane
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
		Rectangle()
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
}

private struct PaneLeafCard: View {
	let pane: PaneLeaf
	let controller: TerminalPaneController
	@ObservedObject var session: TerminalSession
	let isFocused: Bool
	let onFocus: () -> Void

	var body: some View {
		ZStack(alignment: .topLeading) {
			TerminalPaneRepresentable(
				controller: controller,
				isFocused: isFocused,
				onFocus: onFocus
			)
			.background(.black)


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
	}

	private var backgroundStyle: some ShapeStyle {
		if isFocused {
			return AnyShapeStyle(.tint.opacity(0.18))
		}
		return AnyShapeStyle(.quaternary.opacity(0.35))
	}
}

private struct PaneFramePreferenceKey: PreferenceKey {
	static var defaultValue: [PaneID: CGRect] = [:]

	static func reduce(value: inout [PaneID: CGRect], nextValue: () -> [PaneID: CGRect]) {
		value.merge(nextValue(), uniquingKeysWith: { _, new in new })
	}
}
