//
//  ShellModel+PaneTree.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import SwiftUI

// MARK: - Pane Tree Operations
// MARK: Structural editing and traversal helpers for recursive pane layouts.

extension PaneNode {
	nonisolated func leaves() -> [PaneLeaf] {
		switch self {
			case .leaf(let leaf):
				return [leaf]
			case .split(let split):
				return split.first.leaves() + split.second.leaves()
		}
	}

	nonisolated func findPane(id: PaneID) -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf.id == id ? leaf : nil
			case .split(let split):
				return split.first.findPane(id: id) ?? split.second.findPane(id: id)
		}
	}

	nonisolated func containsPane(id: PaneID) -> Bool {
		findPane(id: id) != nil
	}

	nonisolated func firstLeaf() -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf
			case .split(let split):
				return split.first.firstLeaf() ?? split.second.firstLeaf()
		}
	}

	nonisolated func lastLeaf() -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf
			case .split(let split):
				return split.second.lastLeaf() ?? split.first.lastLeaf()
		}
	}

	mutating func split(
		paneID: PaneID,
		direction: SplitDirection,
		newPane: PaneLeaf,
		initialFraction: CGFloat = 0.5
	) -> Bool {
		switch self {
			case .leaf(let leaf):
				guard leaf.id == paneID else {
					return false
				}

				let axis: PaneSplit.Axis = switch direction {
					case .right: .horizontal
					case .down: .vertical
				}

				self = .split(
					PaneSplit(
						axis: axis,
						fraction: initialFraction,
						first: .leaf(leaf),
						second: .leaf(newPane)
					)
				)
				return true

			case .split(var split):
				if split.first.split(
					paneID: paneID,
					direction: direction,
					newPane: newPane,
					initialFraction: initialFraction
				) {
					self = .split(split)
					return true
				}

				if split.second.split(
					paneID: paneID,
					direction: direction,
					newPane: newPane,
					initialFraction: initialFraction
				) {
					self = .split(split)
					return true
				}

				return false
		}
	}

	mutating func removePane(id: PaneID) -> PaneRemovalResult? {
		switch self {
			case .leaf(let leaf):
				return leaf.id == id ? .removedLeaf : nil

			case .split(var split):
				if let result = split.first.removePane(id: id) {
					switch result {
						case .removedLeaf:
							self = split.second
							return .collapsedTo(split.second)
						case .collapsedTo(let node):
							split.first = node
							self = .split(split)
							return .collapsedTo(self)
					}
				}

				if let result = split.second.removePane(id: id) {
					switch result {
						case .removedLeaf:
							self = split.first
							return .collapsedTo(split.first)
						case .collapsedTo(let node):
							split.second = node
							self = .split(split)
							return .collapsedTo(self)
					}
				}

				return nil
		}
	}

	mutating func updateSplitFraction(splitID: SplitID, fraction: CGFloat) -> Bool {
		switch self {
			case .leaf:
				return false

			case .split(var split):
				if split.id == splitID {
					split.fraction = fraction
					self = .split(split)
					return true
				}

				if split.first.updateSplitFraction(splitID: splitID, fraction: fraction) {
					self = .split(split)
					return true
				}

				if split.second.updateSplitFraction(splitID: splitID, fraction: fraction) {
					self = .split(split)
					return true
				}

				return false
		}
	}

	nonisolated func paneCount() -> Int {
		switch self {
			case .leaf:
				return 1
			case .split(let split):
				return split.first.paneCount() + split.second.paneCount()
		}
	}
}
