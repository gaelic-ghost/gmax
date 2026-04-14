//
//  ShellPersistenceController+WorkspaceStore.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import CoreData
import Foundation
import OSLog

extension ShellPersistenceController {
	nonisolated static func syncNode(
		_ node: PaneNode?,
		context: NSManagedObjectContext,
		nodesByID: inout [UUID: PaneNodeEntity],
		retainedNodeIDs: inout Set<UUID>
	) -> PaneNodeEntity? {
		guard let node else {
			return nil
		}

		switch node {
			case .leaf(let leaf):
				let nodeEntity = nodesByID.removeValue(forKey: leaf.id.rawValue)
					?? PaneNodeEntity(context: context)
				nodeEntity.id = leaf.id.rawValue
				nodeEntity.kind = PaneNodeKind.leaf.rawValue
				nodeEntity.sessionID = leaf.sessionID.rawValue
				nodeEntity.axis = nil
				nodeEntity.fraction = 0
				nodeEntity.firstChild = nil
				nodeEntity.secondChild = nil
				retainedNodeIDs.insert(nodeEntity.id)
				return nodeEntity

			case .split(let split):
				let nodeEntity = nodesByID.removeValue(forKey: split.id.rawValue)
					?? PaneNodeEntity(context: context)
				nodeEntity.id = split.id.rawValue
				nodeEntity.kind = PaneNodeKind.split.rawValue
				nodeEntity.sessionID = nil
				nodeEntity.axis = split.axis.rawValue
				nodeEntity.fraction = split.fraction
				nodeEntity.firstChild = syncNode(
					split.first,
					context: context,
					nodesByID: &nodesByID,
					retainedNodeIDs: &retainedNodeIDs
				)
				nodeEntity.secondChild = syncNode(
					split.second,
					context: context,
					nodesByID: &nodesByID,
					retainedNodeIDs: &retainedNodeIDs
				)
				retainedNodeIDs.insert(nodeEntity.id)
				return nodeEntity
		}
	}

	nonisolated static func decodeNode(_ nodeEntity: PaneNodeEntity?, logger: Logger) -> PaneNode? {
		guard let nodeEntity else {
			return nil
		}

		switch PaneNodeKind(rawValue: nodeEntity.kind) {
			case .leaf:
				guard let sessionID = nodeEntity.sessionID else {
					logger.error("A persisted leaf node is missing its session identifier. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				return .leaf(
					PaneLeaf(
						id: PaneID(rawValue: nodeEntity.id),
						sessionID: TerminalSessionID(rawValue: sessionID)
					)
				)

			case .split:
				guard let axis = nodeEntity.axis.flatMap(PaneSplit.Axis.init(rawValue:)) else {
					logger.error("A persisted split node is missing or has an invalid axis. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				guard let first = decodeNode(nodeEntity.firstChild, logger: logger),
					  let second = decodeNode(nodeEntity.secondChild, logger: logger)
				else {
					logger.error("A persisted split node is missing one or both child nodes. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				return .split(
					PaneSplit(
						id: SplitID(rawValue: nodeEntity.id),
						axis: axis,
						fraction: nodeEntity.fraction,
						first: first,
						second: second
					)
				)

			case .none:
				logger.error("A persisted pane node has an unknown kind value. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
				return nil
		}
	}

	nonisolated static func normalizedWorkspace(_ workspace: Workspace, logger: Logger) -> Workspace? {
		guard let root = workspace.root else {
			logger.error("A persisted workspace has no root pane tree. That empty workspace will be discarded during restore. Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
			return nil
		}

		let leaves = root.leaves()
		guard !leaves.isEmpty else {
			logger.error("A persisted workspace decoded to an empty pane tree. That workspace will be discarded during restore. Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
			return nil
		}

		let focusedPaneID = if let focusedPaneID = workspace.focusedPaneID,
			leaves.contains(where: { $0.id == focusedPaneID }) {
			focusedPaneID
		} else {
			leaves[0].id
		}

		return Workspace(
			id: workspace.id,
			title: workspace.title,
			root: root,
			focusedPaneID: focusedPaneID
		)
	}
}
