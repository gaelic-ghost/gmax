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
                switch leaf.content {
                    case let .terminal(sessionID):
                        nodeEntity.contentKind = PersistedPaneContentKind.terminal.rawValue
                        nodeEntity.sessionID = sessionID.rawValue
                        nodeEntity.browserSessionID = nil
                    case let .browser(sessionID):
                        nodeEntity.contentKind = PersistedPaneContentKind.browser.rawValue
                        nodeEntity.sessionID = nil
                        nodeEntity.browserSessionID = sessionID.rawValue
                }
                nodeEntity.axis = nil
                nodeEntity.fraction = 0
                nodeEntity.firstChild = nil
                nodeEntity.secondChild = nil
                return nodeEntity

            case let .split(split):
                let nodeEntity = PaneNodeEntity(context: context)
                nodeEntity.id = split.id.rawValue
                nodeEntity.kind = PaneNodeKind.split.rawValue
                nodeEntity.contentKind = nil
                nodeEntity.sessionID = nil
                nodeEntity.browserSessionID = nil
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
                switch leaf.content {
                    case let .terminal(sessionID):
                        nodeEntity.contentKind = PersistedPaneContentKind.terminal.rawValue
                        nodeEntity.sessionID = sessionID.rawValue
                        nodeEntity.browserSessionID = nil
                    case let .browser(sessionID):
                        nodeEntity.contentKind = PersistedPaneContentKind.browser.rawValue
                        nodeEntity.sessionID = nil
                        nodeEntity.browserSessionID = sessionID.rawValue
                }
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
                nodeEntity.contentKind = nil
                nodeEntity.sessionID = nil
                nodeEntity.browserSessionID = nil
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
                let content: PaneContent
                switch nodeEntity.contentKind.flatMap(PersistedPaneContentKind.init(rawValue:)) {
                    case .terminal:
                        guard let sessionID = nodeEntity.sessionID else {
                            Logger.persistence.error("A persisted terminal leaf node is missing its terminal session identifier. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
                            return nil
                        }
                        content = .terminal(TerminalSessionID(rawValue: sessionID))
                    case .browser:
                        guard let sessionID = nodeEntity.browserSessionID else {
                            Logger.persistence.error("A persisted browser leaf node is missing its browser session identifier. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
                            return nil
                        }
                        content = .browser(BrowserSessionID(rawValue: sessionID))
                    case .none:
                        // Compatibility path for older terminal-only stores.
                        guard let sessionID = nodeEntity.sessionID else {
                            Logger.persistence.error("A persisted leaf node is missing both its content kind and its compatibility terminal session identifier. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
                            return nil
                        }
                        content = .terminal(TerminalSessionID(rawValue: sessionID))
                }

                return .leaf(
                    PaneLeaf(
                        id: PaneID(rawValue: nodeEntity.id),
                        content: content,
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
