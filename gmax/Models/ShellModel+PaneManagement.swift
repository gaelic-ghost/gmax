//
//  ShellModel+PaneManagement.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Pane Lifecycle
// MARK: Pane creation, relaunch, focus, split, close, and split-fraction updates.

extension ShellModel {
	@discardableResult
	func createPane(in workspaceID: WorkspaceID) -> WorkspaceID? {
		guard let workspace = workspace(for: workspaceID) else {
			return nil
		}

		if workspace.root == nil {
			createInitialPane(in: workspace.id)
			return workspace.id
		}

		guard let paneID = workspace.focusedPaneID ?? workspace.root?.firstLeaf()?.id else {
			return workspace.id
		}

		splitPane(paneID, in: workspace.id, direction: .right)
		return workspace.id
	}

	func relaunchPane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		guard let workspace = workspace(for: workspaceID),
			  let pane = workspace.root?.findPane(id: paneID) else {
			paneLogger.error("The app was asked to relaunch a pane, but the target pane could not be resolved inside the selected workspace. The relaunch request was dropped before any shell state changed. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). Pane ID: \(paneID.rawValue.uuidString, privacy: .public)")
			return
		}

		let session = sessions.ensureSession(id: pane.sessionID)
		session.prepareForRelaunch()
		paneLogger.notice("Requested a shell relaunch for the focused pane in a live workspace. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). Pane ID: \(paneID.rawValue.uuidString, privacy: .public). Session ID: \(session.id.rawValue.uuidString, privacy: .public)")
		focusPane(paneID, in: workspaceID)
	}

	func relaunchFocusedPane(in workspaceID: WorkspaceID) {
		guard
			let workspace = workspace(for: workspaceID),
			let paneID = workspace.focusedPaneID
		else {
			return
		}

		relaunchPane(paneID, in: workspace.id)
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
		guard let sourcePane = root.findPane(id: paneID) else {
			return
		}

		let sourceSession = sessions.ensureSession(id: sourcePane.sessionID)
		let inheritedCurrentDirectory = sourceSession.currentDirectory
			?? sourceSession.launchConfiguration.currentDirectory

		let newPane = PaneLeaf()
		guard root.split(
			paneID: paneID,
			direction: direction,
			newPane: newPane
		) else {
			return
		}

		workspaces[workspaceIndex].root = root
		_ = sessions.ensureSession(
			id: newPane.sessionID,
			launchConfiguration: launchContextBuilder.makeLaunchConfiguration(
				currentDirectory: inheritedCurrentDirectory
			)
		)
		workspaces[workspaceIndex].focusedPaneID = newPane.id
		recordPaneFocus(newPane.id, in: workspaceID)
		schedulePersistenceSave()
	}

	func splitFocusedPane(in workspaceID: WorkspaceID, _ direction: SplitDirection) {
		guard
			let workspace = workspace(for: workspaceID),
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

		guard root.removePane(id: paneID) != nil else {
			return
		}

		let survivingLeaves = root.leaves()
		workspaces[workspaceIndex].root = survivingLeaves.isEmpty ? nil : root
		removeUnreferencedSessions()

		guard !survivingLeaves.isEmpty else {
			workspaces[workspaceIndex].focusedPaneID = nil
			paneFramesByWorkspace.removeValue(forKey: workspaceID)
			paneFocusHistoryByWorkspace.removeValue(forKey: workspaceID)
			schedulePersistenceSave()
			return
		}

		if let priorFocusedPaneID,
		   survivingLeaves.contains(where: { $0.id == priorFocusedPaneID }) {
			workspaces[workspaceIndex].focusedPaneID = priorFocusedPaneID
			recordPaneFocus(priorFocusedPaneID, in: workspaceID)
			schedulePersistenceSave()
			return
		}

		let removedPaneIndex = priorLeaves.firstIndex(where: { $0.id == paneID }) ?? survivingLeaves.endIndex
		let fallbackIndex = min(removedPaneIndex, survivingLeaves.count - 1)
		workspaces[workspaceIndex].focusedPaneID = survivingLeaves[fallbackIndex].id
		recordPaneFocus(survivingLeaves[fallbackIndex].id, in: workspaceID)
		schedulePersistenceSave()
	}

	@discardableResult
	func closeFocusedPane(in workspaceID: WorkspaceID) -> CloseCommandOutcome {
		guard let workspace = workspace(for: workspaceID) else {
			return CloseCommandOutcome(result: .noAction, nextSelectedWorkspaceID: normalizedWorkspaceSelection(workspaceID))
		}

		guard let focusedPaneID = workspace.focusedPaneID else {
			return CloseCommandOutcome(result: .noAction, nextSelectedWorkspaceID: normalizedWorkspaceSelection(workspaceID))
		}

		if workspace.paneCount == 1 {
			guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspace.id }) else {
				return CloseCommandOutcome(result: .noAction, nextSelectedWorkspaceID: normalizedWorkspaceSelection(workspaceID))
			}

			workspaces[workspaceIndex].root = nil
			workspaces[workspaceIndex].focusedPaneID = nil
			paneFramesByWorkspace.removeValue(forKey: workspace.id)
			paneFocusHistoryByWorkspace.removeValue(forKey: workspace.id)
			removeUnreferencedSessions()
			schedulePersistenceSave()
			return CloseCommandOutcome(result: .closedPane, nextSelectedWorkspaceID: workspace.id)
		}

		closePane(focusedPaneID, in: workspace.id)
		return CloseCommandOutcome(result: .closedPane, nextSelectedWorkspaceID: normalizedWorkspaceSelection(workspaceID))
	}

	func movePaneFocus(_ direction: PaneFocusDirection, in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}

		let leaves = workspaces[workspaceIndex].paneLeaves
		guard !leaves.isEmpty else { return }

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
}

// MARK: - Pane Navigation Helpers
// MARK: Internal helpers that keep pane focus history, geometry, and controller state in sync.

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

	func removeUnreferencedSessions() {
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

	func recordPaneFocus(_ paneID: PaneID, in workspaceID: WorkspaceID) {
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
