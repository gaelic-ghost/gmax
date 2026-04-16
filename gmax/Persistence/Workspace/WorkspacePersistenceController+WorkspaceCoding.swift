/*
 WorkspacePersistenceController+WorkspaceCoding owns translation between the
 in-memory workspace model and the Core Data graph. It encodes and decodes pane
 trees, snapshot trees, and session snapshot relationships so the repository
 layer can persist workspace state without leaking managed object details.
 */

import CoreData
import Foundation
import OSLog

extension WorkspacePersistenceController {
	nonisolated static func makeNodeEntity(
		from node: PaneNode?,
		context: NSManagedObjectContext
	) -> PaneNodeEntity? {
		guard let node else {
			return nil
		}

		switch node {
			case .leaf(let leaf):
				let nodeEntity = PaneNodeEntity(context: context)
				nodeEntity.id = leaf.id.rawValue
				nodeEntity.kind = PaneNodeKind.leaf.rawValue
				nodeEntity.sessionID = leaf.sessionID.rawValue
				nodeEntity.axis = nil
				nodeEntity.fraction = 0
				nodeEntity.firstChild = nil
				nodeEntity.secondChild = nil
				return nodeEntity

			case .split(let split):
				let nodeEntity = PaneNodeEntity(context: context)
				nodeEntity.id = split.id.rawValue
				nodeEntity.kind = PaneNodeKind.split.rawValue
				nodeEntity.sessionID = nil
				nodeEntity.axis = split.axis.rawValue
				nodeEntity.fraction = split.fraction
				nodeEntity.firstChild = makeNodeEntity(from: split.first, context: context)
				nodeEntity.secondChild = makeNodeEntity(from: split.second, context: context)
				return nodeEntity
		}
	}

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

	nonisolated static func decodeNode(_ nodeEntity: PaneNodeEntity?) -> PaneNode? {
		guard let nodeEntity else {
			return nil
		}

		switch PaneNodeKind(rawValue: nodeEntity.kind) {
			case .leaf:
				guard let sessionID = nodeEntity.sessionID else {
					Logger.persistence.error("A persisted leaf node is missing its session identifier. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
					Logger.persistence.error("A persisted split node is missing or has an invalid axis. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				guard let first = decodeNode(nodeEntity.firstChild),
					  let second = decodeNode(nodeEntity.secondChild)
				else {
					Logger.persistence.error("A persisted split node is missing one or both child nodes. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
				Logger.persistence.error("A persisted pane node has an unknown kind value. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
				return nil
		}
	}

	nonisolated static func syncSnapshotNode(
		_ node: PaneNode?,
		context: NSManagedObjectContext,
		sessionSnapshotsByID: [UUID: PaneSessionSnapshotEntity]
	) throws -> PaneSnapshotNodeEntity? {
		guard let node else {
			return nil
		}

		switch node {
			case .leaf(let leaf):
				guard let sessionSnapshot = sessionSnapshotsByID[leaf.sessionID.rawValue] else {
					throw SnapshotPersistenceError.missingSessionSnapshot(sessionID: leaf.sessionID.rawValue)
				}

				let nodeEntity = PaneSnapshotNodeEntity(context: context)
				nodeEntity.id = leaf.id.rawValue
				nodeEntity.kind = PaneNodeKind.leaf.rawValue
				nodeEntity.sessionSnapshotID = sessionSnapshot.id
				nodeEntity.axis = nil
				nodeEntity.fraction = 0
				nodeEntity.firstChild = nil
				nodeEntity.secondChild = nil
				return nodeEntity

			case .split(let split):
				let nodeEntity = PaneSnapshotNodeEntity(context: context)
				nodeEntity.id = split.id.rawValue
				nodeEntity.kind = PaneNodeKind.split.rawValue
				nodeEntity.sessionSnapshotID = nil
				nodeEntity.axis = split.axis.rawValue
				nodeEntity.fraction = split.fraction
				nodeEntity.firstChild = try syncSnapshotNode(
					split.first,
					context: context,
					sessionSnapshotsByID: sessionSnapshotsByID
				)
				nodeEntity.secondChild = try syncSnapshotNode(
					split.second,
					context: context,
					sessionSnapshotsByID: sessionSnapshotsByID
				)
				return nodeEntity
		}
	}

	nonisolated static func decodeSnapshotNode(_ nodeEntity: PaneSnapshotNodeEntity?) -> PaneNode? {
		guard let nodeEntity else {
			return nil
		}

		switch PaneNodeKind(rawValue: nodeEntity.kind) {
			case .leaf:
				guard let sessionSnapshotID = nodeEntity.sessionSnapshotID else {
					Logger.persistence.error("A saved workspace snapshot leaf node is missing its session snapshot identifier. That pane will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				return .leaf(
					PaneLeaf(
						id: PaneID(rawValue: nodeEntity.id),
						sessionID: TerminalSessionID(rawValue: sessionSnapshotID)
					)
				)

			case .split:
				guard let axis = nodeEntity.axis.flatMap(PaneSplit.Axis.init(rawValue:)) else {
					Logger.persistence.error("A saved workspace snapshot split node is missing or has an invalid axis. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				guard let first = decodeSnapshotNode(nodeEntity.firstChild),
					  let second = decodeSnapshotNode(nodeEntity.secondChild)
				else {
					Logger.persistence.error("A saved workspace snapshot split node is missing one or both child nodes. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
				Logger.persistence.error("A saved workspace snapshot pane node has an unknown kind value. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
				return nil
		}
	}
}
