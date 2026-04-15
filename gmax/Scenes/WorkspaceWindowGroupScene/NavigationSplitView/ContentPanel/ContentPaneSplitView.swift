//
//  ContentPaneSplitView.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import AppKit
import SwiftUI

struct ContentPaneSplitView<First: View, Second: View>: View {
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
			let clampedFraction = clamped(fraction, for: primaryLength)
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
		let currentFraction = clamped(fraction, for: totalLength)

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
			.accessibilityLabel(axis == .horizontal ? "Vertical pane divider" : "Horizontal pane divider")
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
