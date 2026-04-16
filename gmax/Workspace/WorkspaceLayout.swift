import Foundation
import SwiftUI

struct WorkspaceID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue = UUID()

	var id: UUID { rawValue }
}

struct PaneID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue = UUID()

	var id: UUID { rawValue }
}

struct SplitID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue = UUID()

	var id: UUID { rawValue }
}

enum SplitDirection {
	case right
	case down
}

enum PaneFocusDirection {
	case next
	case previous
	case left
	case right
	case up
	case down
}

struct Workspace: Identifiable, Hashable, Codable {
	var id = WorkspaceID()
	var title: String
	var root: PaneNode? = nil
	var savedWorkspaceID: SavedWorkspaceID? = nil

	var paneLeaves: [PaneLeaf] {
		root?.leaves() ?? []
	}

	var paneCount: Int {
		paneLeaves.count
	}
}

indirect enum PaneNode: Hashable, Codable {
	case leaf(PaneLeaf)
	case split(PaneSplit)
}

struct PaneLeaf: Identifiable, Hashable, Codable {
	var id = PaneID()
	var sessionID = TerminalSessionID()
}

struct PaneSplit: Hashable, Codable {
	enum Axis: String, Hashable, Codable {
		case horizontal
		case vertical
	}

	var id = SplitID()
	var axis: Axis
	var fraction: CGFloat
	var first: PaneNode
	var second: PaneNode
}

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

	nonisolated func firstLeaf() -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf
			case .split(let split):
				return split.first.firstLeaf() ?? split.second.firstLeaf()
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

	nonisolated func removingPane(id: PaneID) -> PaneNode? {
		switch self {
			case .leaf(let leaf):
				return leaf.id == id ? nil : self

			case .split(let split):
				let first = split.first.removingPane(id: id)
				let second = split.second.removingPane(id: id)

				switch (first, second) {
					case (nil, nil):
						return nil
					case (let remaining?, nil):
						return remaining
					case (nil, let remaining?):
						return remaining
					case (let first?, let second?):
						return .split(
							PaneSplit(
								id: split.id,
								axis: split.axis,
								fraction: split.fraction,
								first: first,
								second: second
							)
						)
				}
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
}
