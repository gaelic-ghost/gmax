/*
 WorkspacePersistenceController+WorkspaceCoding owns translation between the
 in-memory workspace model and the active Core Data payload graph.
 */

import CoreData
import Foundation
import OSLog

extension WorkspacePersistenceController {
    nonisolated static func makeNodeEntity(
        from node: PaneNode?,
        context: NSManagedObjectContext,
    ) -> PaneNodeEntity? {
        guard let node else {
            return nil
        }

        switch node {
            case let .leaf(leaf):
                let nodeEntity = PaneNodeEntity(context: context)
                nodeEntity.id = leaf.id.rawValue
                nodeEntity.kind = PaneNodeKind.leaf.rawValue
                nodeEntity.sessionID = leaf.sessionID.rawValue
                nodeEntity.axis = nil
                nodeEntity.fraction = 0
                nodeEntity.firstChild = nil
                nodeEntity.secondChild = nil
                return nodeEntity

            case let .split(split):
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
        retainedNodeIDs: inout Set<UUID>,
    ) -> PaneNodeEntity? {
        guard let node else {
            return nil
        }

        switch node {
            case let .leaf(leaf):
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

            case let .split(split):
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
                    retainedNodeIDs: &retainedNodeIDs,
                )
                nodeEntity.secondChild = syncNode(
                    split.second,
                    context: context,
                    nodesByID: &nodesByID,
                    retainedNodeIDs: &retainedNodeIDs,
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
                        sessionID: TerminalSessionID(rawValue: sessionID),
                    ),
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
                        second: second,
                    ),
                )

            case .none:
                Logger.persistence.error("A persisted pane node has an unknown kind value. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
                return nil
        }
    }
}
