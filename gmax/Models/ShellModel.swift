//
//  ShellModel.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import Combine
import SwiftUI

struct WorkspaceID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

struct PaneID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

struct SplitID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

struct TerminalSessionID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
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

enum CloseCommandResult {
	case closedPane
	case emptiedWorkspace
	case closedWorkspace
	case closeWindow
	case noAction
}

struct Workspace: Identifiable, Hashable, Codable {
	var id: WorkspaceID
	var title: String
	var root: PaneNode?
	var focusedPaneID: PaneID?

	init(
		id: WorkspaceID = WorkspaceID(),
		title: String,
		root: PaneNode? = nil,
		focusedPaneID: PaneID? = nil
	) {
		self.id = id
		self.title = title
		self.root = root
		self.focusedPaneID = focusedPaneID
	}
}

extension Workspace {
	var paneLeaves: [PaneLeaf] {
		root?.leaves() ?? []
	}

	var paneCount: Int {
		root?.paneCount() ?? 0
	}
}

indirect enum PaneNode: Hashable, Codable {
	case leaf(PaneLeaf)
	case split(PaneSplit)
}

struct PaneLeaf: Identifiable, Hashable, Codable {
	var id: PaneID
	var sessionID: TerminalSessionID

	init(id: PaneID = PaneID(), sessionID: TerminalSessionID = TerminalSessionID()) {
		self.id = id
		self.sessionID = sessionID
	}
}

struct PaneSplit: Hashable, Codable {
	enum Axis: String, Hashable, Codable {
		case horizontal
		case vertical
	}

	var id: SplitID
	var axis: Axis
	var fraction: CGFloat
	var first: PaneNode
	var second: PaneNode

	init(
		id: SplitID = SplitID(),
		axis: Axis,
		fraction: CGFloat,
		first: PaneNode,
		second: PaneNode
	) {
		self.id = id
		self.axis = axis
		self.fraction = fraction
		self.first = first
		self.second = second
	}
}

enum PaneRemovalResult {
	case removedLeaf
	case collapsedTo(PaneNode)
}

extension PaneNode {
	func leaves() -> [PaneLeaf] {
		switch self {
			case .leaf(let leaf):
				return [leaf]
			case .split(let split):
				return split.first.leaves() + split.second.leaves()
		}
	}

	func findPane(id: PaneID) -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf.id == id ? leaf : nil
			case .split(let split):
				return split.first.findPane(id: id) ?? split.second.findPane(id: id)
		}
	}

	func containsPane(id: PaneID) -> Bool {
		findPane(id: id) != nil
	}

	func firstLeaf() -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf
			case .split(let split):
				return split.first.firstLeaf() ?? split.second.firstLeaf()
		}
	}

	func lastLeaf() -> PaneLeaf? {
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

	func paneCount() -> Int {
		switch self {
			case .leaf:
				return 1
			case .split(let split):
				return split.first.paneCount() + split.second.paneCount()
		}
	}
}

@MainActor
final class ShellModel: ObservableObject {
	@Published var workspaces: [Workspace]
	@Published var selectedWorkspaceID: WorkspaceID?
	@Published var columnVisibility: NavigationSplitViewVisibility
	@Published var isInspectorVisible: Bool

	let persistence: ShellPersistenceController
	let sessions: TerminalSessionRegistry
	let paneControllers: TerminalPaneControllerStore
	private var paneFramesByWorkspace: [WorkspaceID: [PaneID: CGRect]]
	private var paneFocusHistoryByWorkspace: [WorkspaceID: [PaneID]]
	private var pendingPersistenceTask: Task<Void, Never>?

	init() {
		let persistence = ShellPersistenceController.shared
		let persistedWorkspaces = persistence.loadWorkspaces()
		let workspaces = persistedWorkspaces.isEmpty ? Self.sampleWorkspaces : persistedWorkspaces
		self.persistence = persistence
		self.sessions = TerminalSessionRegistry(workspaces: workspaces)
			self.paneControllers = TerminalPaneControllerStore()
			self.workspaces = workspaces
			self.selectedWorkspaceID = workspaces.first?.id
			self.columnVisibility = .all
			self.isInspectorVisible = true
			self.paneFramesByWorkspace = [:]
			self.paneFocusHistoryByWorkspace = Self.initialFocusHistory(for: workspaces)
		}

	convenience init(
		workspaces: [Workspace],
		selectedWorkspaceID: WorkspaceID?,
		columnVisibility: NavigationSplitViewVisibility = .all,
		isInspectorVisible: Bool = true
	) {
		self.init(
			workspaces: workspaces,
			selectedWorkspaceID: selectedWorkspaceID,
			persistence: .shared,
			columnVisibility: columnVisibility,
			isInspectorVisible: isInspectorVisible
		)
	}

	init(
		workspaces: [Workspace],
		selectedWorkspaceID: WorkspaceID?,
		persistence: ShellPersistenceController,
		columnVisibility: NavigationSplitViewVisibility = .all,
		isInspectorVisible: Bool = true
	) {
		self.persistence = persistence
		self.sessions = TerminalSessionRegistry(workspaces: workspaces)
		self.paneControllers = TerminalPaneControllerStore()
		self.workspaces = workspaces
		self.selectedWorkspaceID = selectedWorkspaceID
		self.columnVisibility = columnVisibility
		self.isInspectorVisible = isInspectorVisible
		self.paneFramesByWorkspace = [:]
		self.paneFocusHistoryByWorkspace = Self.initialFocusHistory(for: workspaces)
	}

	var selectedWorkspaceIndex: Int? {
		guard let selectedWorkspaceID else {
			return nil
		}
		return workspaces.firstIndex { $0.id == selectedWorkspaceID }
	}

	var selectedWorkspace: Workspace? {
		guard let selectedWorkspaceIndex else {
			return nil
		}
		return workspaces[selectedWorkspaceIndex]
	}

	var focusedPane: PaneLeaf? {
		guard
			let workspace = selectedWorkspace,
			let root = workspace.root,
			let focusedPaneID = workspace.focusedPaneID
		else {
			return nil
		}
		return root.findPane(id: focusedPaneID)
	}

	func selectWorkspace(_ workspaceID: WorkspaceID) {
		selectedWorkspaceID = workspaceID
	}

	func selectNextWorkspace() {
		guard !workspaces.isEmpty else {
			return
		}
		guard let selectedWorkspaceIndex else {
			selectedWorkspaceID = workspaces.first?.id
			return
		}

		let nextIndex = (selectedWorkspaceIndex + 1) % workspaces.count
		selectedWorkspaceID = workspaces[nextIndex].id
	}

	func selectPreviousWorkspace() {
		guard !workspaces.isEmpty else {
			return
		}
		guard let selectedWorkspaceIndex else {
			selectedWorkspaceID = workspaces.last?.id
			return
		}

		let previousIndex = (selectedWorkspaceIndex - 1 + workspaces.count) % workspaces.count
		selectedWorkspaceID = workspaces[previousIndex].id
	}

	func focusPane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard let root = workspaces[workspaceIndex].root,
			  root.containsPane(id: paneID)
		else {
			return
		}
		workspaces[workspaceIndex].focusedPaneID = paneID
		recordPaneFocus(paneID, in: workspaceID)
		schedulePersistenceSave()
	}

	func splitPane(_ paneID: PaneID, in workspaceID: WorkspaceID, direction: SplitDirection) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard var root = workspaces[workspaceIndex].root else {
			return
		}

		let newPane = PaneLeaf()
		guard root.split(
			paneID: paneID,
			direction: direction,
			newPane: newPane
		) else {
			return
		}

		workspaces[workspaceIndex].root = root
		_ = sessions.ensureSession(id: newPane.sessionID)
		workspaces[workspaceIndex].focusedPaneID = newPane.id
		recordPaneFocus(newPane.id, in: workspaceID)
		schedulePersistenceSave()
	}

	func splitFocusedPane(_ direction: SplitDirection) {
		guard
			let workspace = selectedWorkspace,
			let paneID = workspace.focusedPaneID
		else {
			return
		}

		splitPane(paneID, in: workspace.id, direction: direction)
	}

	func closePane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard var root = workspaces[workspaceIndex].root else {
			return
		}

		let priorLeaves = root.leaves()
		let priorFocusedPaneID = workspaces[workspaceIndex].focusedPaneID

		if root.paneCount() == 1 {
			guard root.findPane(id: paneID) != nil else {
				return
			}
			workspaces[workspaceIndex].root = nil
			workspaces[workspaceIndex].focusedPaneID = nil
			removeUnreferencedSessions()
			schedulePersistenceSave()
			return
		}

		guard root.removePane(id: paneID) != nil else {
			return
		}

		workspaces[workspaceIndex].root = root
		removeUnreferencedSessions()

		let survivingLeaves = workspaces[workspaceIndex].paneLeaves
		if let priorFocusedPaneID,
		   survivingLeaves.contains(where: { $0.id == priorFocusedPaneID }) {
			workspaces[workspaceIndex].focusedPaneID = priorFocusedPaneID
			recordPaneFocus(priorFocusedPaneID, in: workspaceID)
			schedulePersistenceSave()
			return
		}

		guard !survivingLeaves.isEmpty else {
			workspaces[workspaceIndex].focusedPaneID = nil
			schedulePersistenceSave()
			return
		}

		let removedPaneIndex = priorLeaves.firstIndex(where: { $0.id == paneID }) ?? survivingLeaves.endIndex
		let fallbackIndex = min(removedPaneIndex, survivingLeaves.count - 1)
		workspaces[workspaceIndex].focusedPaneID = survivingLeaves[fallbackIndex].id
		recordPaneFocus(survivingLeaves[fallbackIndex].id, in: workspaceID)
		schedulePersistenceSave()
	}

	func closeFocusedPane() {
		guard
			let workspace = selectedWorkspace,
			let paneID = workspace.focusedPaneID
		else {
			return
		}

		closePane(paneID, in: workspace.id)
	}

	func movePaneFocus(_ direction: PaneFocusDirection) {
		guard let workspaceIndex = selectedWorkspaceIndex else {
			return
		}

		let leaves = workspaces[workspaceIndex].paneLeaves
		guard !leaves.isEmpty else {
			workspaces[workspaceIndex].focusedPaneID = nil
			return
		}

		guard let focusedPaneID = workspaces[workspaceIndex].focusedPaneID,
			  let focusedIndex = leaves.firstIndex(where: { $0.id == focusedPaneID })
		else {
			let fallbackPane = direction == .next ? leaves.first : leaves.last
			workspaces[workspaceIndex].focusedPaneID = fallbackPane?.id
			return
		}

		let nextIndex: Int
		switch direction {
			case .next:
				nextIndex = (focusedIndex + 1) % leaves.count
			case .previous:
				nextIndex = (focusedIndex - 1 + leaves.count) % leaves.count
			case .left, .right, .up, .down:
				guard let nextPaneID = directionalPaneFocus(
					from: focusedPaneID,
					in: workspaces[workspaceIndex].id,
					direction: direction
				) else {
					return
				}
				workspaces[workspaceIndex].focusedPaneID = nextPaneID
				recordPaneFocus(nextPaneID, in: workspaces[workspaceIndex].id)
				return
		}

		workspaces[workspaceIndex].focusedPaneID = leaves[nextIndex].id
		recordPaneFocus(leaves[nextIndex].id, in: workspaces[workspaceIndex].id)
	}

	func workspace(for workspaceID: WorkspaceID) -> Workspace? {
		workspaces.first { $0.id == workspaceID }
	}

	func toggleSidebar() {
		columnVisibility = columnVisibility == .all ? .doubleColumn : .all
	}

	func toggleInspector() {
		isInspectorVisible.toggle()
	}

	func controller(for pane: PaneLeaf) -> TerminalPaneController {
		let session = sessions.ensureSession(id: pane.sessionID)
		return paneControllers.controller(for: pane, session: session)
	}

	func setSplitFraction(_ fraction: CGFloat, for splitID: SplitID, in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard var root = workspaces[workspaceIndex].root else {
			return
		}

		guard root.updateSplitFraction(splitID: splitID, fraction: fraction) else {
			return
		}
		workspaces[workspaceIndex].root = root
		schedulePersistenceSave()
	}

	func updatePaneFrames(_ paneFrames: [PaneID: CGRect], in workspaceID: WorkspaceID) {
		paneFramesByWorkspace[workspaceID] = paneFrames
	}

	private func removeUnreferencedSessions() {
		let activeLeaves = workspaces.flatMap { workspace in
			workspace.paneLeaves.map { (workspace.id, $0) }
		}
		let activeSessionIDs = Set(activeLeaves.map(\.1.sessionID))
		let activePaneIDsByWorkspace = Dictionary(grouping: activeLeaves, by: \.0)
			.mapValues { Set($0.map(\.1.id)) }
		sessions.removeSessions(notIn: activeSessionIDs)
		paneControllers.removeControllers(notIn: Set(activeLeaves.map(\.1.id)))

		var filteredFramesByWorkspace: [WorkspaceID: [PaneID: CGRect]] = [:]
		for (workspaceID, frames) in paneFramesByWorkspace {
			guard let activePaneIDs = activePaneIDsByWorkspace[workspaceID] else {
				continue
			}
			let filteredFrames = frames.filter { activePaneIDs.contains($0.key) }
			if !filteredFrames.isEmpty {
				filteredFramesByWorkspace[workspaceID] = filteredFrames
			}
		}
		paneFramesByWorkspace = filteredFramesByWorkspace

		var filteredFocusHistoryByWorkspace: [WorkspaceID: [PaneID]] = [:]
		for (workspaceID, history) in paneFocusHistoryByWorkspace {
			guard let activePaneIDs = activePaneIDsByWorkspace[workspaceID] else {
				continue
			}
			let filteredHistory = history.filter { activePaneIDs.contains($0) }
			if !filteredHistory.isEmpty {
				filteredFocusHistoryByWorkspace[workspaceID] = filteredHistory
			}
		}
		paneFocusHistoryByWorkspace = filteredFocusHistoryByWorkspace
	}

	private func recordPaneFocus(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		var history = paneFocusHistoryByWorkspace[workspaceID, default: []]
		history.removeAll { $0 == paneID }
		history.append(paneID)
		paneFocusHistoryByWorkspace[workspaceID] = history
	}

	private func directionalPaneFocus(
		from paneID: PaneID,
		in workspaceID: WorkspaceID,
		direction: PaneFocusDirection
	) -> PaneID? {
		guard let currentFrame = paneFramesByWorkspace[workspaceID]?[paneID] else {
			return nil
		}

		let paneFrames = Array(paneFramesByWorkspace[workspaceID] ?? [:])
		let candidates: [(PaneID, PaneNavigationMetrics)] = paneFrames.compactMap { entry in
			let (candidatePaneID, candidateFrame) = entry
			guard candidatePaneID != paneID else {
				return nil
			}

			guard let metrics = navigationMetrics(
				from: currentFrame,
				to: candidateFrame,
				direction: direction,
				history: paneFocusHistoryByWorkspace[workspaceID, default: []],
				paneID: candidatePaneID
			) else {
				return nil
			}

			return (candidatePaneID, metrics)
		}

		return candidates.max { lhs, rhs in
			lhs.1 < rhs.1
		}?.0
	}

	private func navigationMetrics(
		from currentFrame: CGRect,
		to candidateFrame: CGRect,
		direction: PaneFocusDirection,
		history: [PaneID],
		paneID: PaneID
	) -> PaneNavigationMetrics? {
		let directionalDistance: CGFloat
		let perpendicularOverlap: CGFloat
		let perpendicularDistance: CGFloat

		switch direction {
			case .left:
				guard candidateFrame.midX < currentFrame.midX else { return nil }
				directionalDistance = max(currentFrame.minX - candidateFrame.maxX, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minY,
					currentMax: currentFrame.maxY,
					candidateMin: candidateFrame.minY,
					candidateMax: candidateFrame.maxY
				)
				perpendicularDistance = abs(candidateFrame.midY - currentFrame.midY)

			case .right:
				guard candidateFrame.midX > currentFrame.midX else { return nil }
				directionalDistance = max(candidateFrame.minX - currentFrame.maxX, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minY,
					currentMax: currentFrame.maxY,
					candidateMin: candidateFrame.minY,
					candidateMax: candidateFrame.maxY
				)
				perpendicularDistance = abs(candidateFrame.midY - currentFrame.midY)

			case .up:
				guard candidateFrame.midY < currentFrame.midY else { return nil }
				directionalDistance = max(currentFrame.minY - candidateFrame.maxY, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minX,
					currentMax: currentFrame.maxX,
					candidateMin: candidateFrame.minX,
					candidateMax: candidateFrame.maxX
				)
				perpendicularDistance = abs(candidateFrame.midX - currentFrame.midX)

			case .down:
				guard candidateFrame.midY > currentFrame.midY else { return nil }
				directionalDistance = max(candidateFrame.minY - currentFrame.maxY, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minX,
					currentMax: currentFrame.maxX,
					candidateMin: candidateFrame.minX,
					candidateMax: candidateFrame.maxX
				)
				perpendicularDistance = abs(candidateFrame.midX - currentFrame.midX)

			case .next, .previous:
				return nil
		}

		let historyRank = history.lastIndex(of: paneID).map { history.distance(from: $0, to: history.endIndex) } ?? 0
		return PaneNavigationMetrics(
			hasPerpendicularOverlap: perpendicularOverlap > 0,
			perpendicularOverlap: perpendicularOverlap,
			directionalDistance: directionalDistance,
			perpendicularDistance: perpendicularDistance,
			historyRank: historyRank
		)
	}

	private func overlapLength(
		currentMin: CGFloat,
		currentMax: CGFloat,
		candidateMin: CGFloat,
		candidateMax: CGFloat
	) -> CGFloat {
		max(0, min(currentMax, candidateMax) - max(currentMin, candidateMin))
	}
}

extension ShellModel {
	private struct PaneNavigationMetrics: Comparable {
		let hasPerpendicularOverlap: Bool
		let perpendicularOverlap: CGFloat
		let directionalDistance: CGFloat
		let perpendicularDistance: CGFloat
		let historyRank: Int

		static func < (lhs: Self, rhs: Self) -> Bool {
			if lhs.hasPerpendicularOverlap != rhs.hasPerpendicularOverlap {
				return !lhs.hasPerpendicularOverlap && rhs.hasPerpendicularOverlap
			}
			if lhs.perpendicularOverlap != rhs.perpendicularOverlap {
				return lhs.perpendicularOverlap < rhs.perpendicularOverlap
			}
			if lhs.directionalDistance != rhs.directionalDistance {
				return lhs.directionalDistance > rhs.directionalDistance
			}
			if lhs.perpendicularDistance != rhs.perpendicularDistance {
				return lhs.perpendicularDistance > rhs.perpendicularDistance
			}
			return lhs.historyRank < rhs.historyRank
		}
	}

	private static func initialFocusHistory(for workspaces: [Workspace]) -> [WorkspaceID: [PaneID]] {
		Dictionary(uniqueKeysWithValues: workspaces.map { workspace in
			(workspace.id, workspace.focusedPaneID.map { [$0] } ?? [])
		})
	}

	func performCloseCommand() -> CloseCommandResult {
		guard let workspaceIndex = selectedWorkspaceIndex else {
			return .closeWindow
		}

		let workspaceID = workspaces[workspaceIndex].id
		if let focusedPaneID = workspaces[workspaceIndex].focusedPaneID {
			closePane(focusedPaneID, in: workspaceID)
			return workspaces[workspaceIndex].root == nil ? .emptiedWorkspace : .closedPane
		}

		guard workspaces[workspaceIndex].root == nil else {
			return .noAction
		}

		if workspaces.count > 1 {
			let removedWorkspaceID = workspaces[workspaceIndex].id
			workspaces.remove(at: workspaceIndex)
			paneFramesByWorkspace.removeValue(forKey: removedWorkspaceID)
			paneFocusHistoryByWorkspace.removeValue(forKey: removedWorkspaceID)
			let nextIndex = min(workspaceIndex, workspaces.count - 1)
			selectedWorkspaceID = workspaces[nextIndex].id
			schedulePersistenceSave()
			return .closedWorkspace
		}

		return .closeWindow
	}

	private func schedulePersistenceSave() {
		pendingPersistenceTask?.cancel()
		let workspacesSnapshot = workspaces
		pendingPersistenceTask = Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(250))
			guard !Task.isCancelled else {
				return
			}
			persistence.save(workspaces: workspacesSnapshot)
		}
	}

	static let sampleWorkspaces: [Workspace] = {
		let workspaceOneRootLeaf = PaneLeaf()
		let workspaceOneTopRightLeaf = PaneLeaf()
		let workspaceOneBottomRightLeaf = PaneLeaf()

		let workspaceOne = Workspace(
			title: "Workspace One",
			root: .split(
				PaneSplit(
					axis: .horizontal,
					fraction: 0.5,
					first: .leaf(workspaceOneRootLeaf),
					second: .split(
						PaneSplit(
							axis: .vertical,
							fraction: 0.5,
							first: .leaf(workspaceOneTopRightLeaf),
							second: .leaf(workspaceOneBottomRightLeaf)
						)
					)
				)
			),
			focusedPaneID: workspaceOneBottomRightLeaf.id
		)

		let workspaceTwoLeaf = PaneLeaf()
		let workspaceTwo = Workspace(
			title: "Workspace Two",
			root: .leaf(workspaceTwoLeaf),
			focusedPaneID: workspaceTwoLeaf.id
		)

		return [workspaceOne, workspaceTwo]
	}()
}
