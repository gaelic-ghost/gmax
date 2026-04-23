/*
 WorkspacePersistenceEntities defines the active Core Data managed object
 surface for workspace persistence. These entities model the current payload
 plus placement store used by live, recent, and library workspace state.
 */

import CoreData
import Foundation

enum PaneNodeKind: String {
    case leaf
    case split
}

@objc(WorkspaceEntity)
final class WorkspaceEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var lastActiveAt: Date
    @NSManaged var notes: String?
    @NSManaged var previewText: String?
    @NSManaged var searchText: String?
    @NSManaged var sortOrder: Int64
    @NSManaged var rootNode: PaneNodeEntity?
    @NSManaged var placements: NSSet?
    @NSManaged var sessionSnapshots: NSSet?
}

@objc(PaneNodeEntity)
final class PaneNodeEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var kind: String
    @NSManaged var sessionID: UUID?
    @NSManaged var axis: String?
    @NSManaged var fraction: Double
    @NSManaged var workspaceRoot: WorkspaceEntity?
    @NSManaged var firstChild: PaneNodeEntity?
    @NSManaged var firstParent: PaneNodeEntity?
    @NSManaged var secondChild: PaneNodeEntity?
    @NSManaged var secondParent: PaneNodeEntity?
}

@objc(WorkspacePlacementEntity)
final class WorkspacePlacementEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var role: String
    @NSManaged var windowID: UUID?
    @NSManaged var sortOrder: Int64
    @NSManaged var restoreSortOrder: Int64
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var lastOpenedAt: Date?
    @NSManaged var isPinned: Bool
    @NSManaged var title: String
    @NSManaged var previewText: String?
    @NSManaged var searchText: String?
    @NSManaged var paneCount: Int64
    @NSManaged var workspace: WorkspaceEntity?
}

@objc(WorkspaceWindowStateEntity)
final class WorkspaceWindowStateEntity: NSManagedObject {
    @NSManaged var windowID: UUID
    @NSManaged var selectedWorkspaceID: UUID?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

@objc(PaneSessionSnapshotEntity)
final class PaneSessionSnapshotEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var executable: String
    @NSManaged var argumentsData: Data?
    @NSManaged var environmentData: Data?
    @NSManaged var currentDirectory: String?
    @NSManaged var title: String
    @NSManaged var transcript: String?
    @NSManaged var transcriptByteCount: Int64
    @NSManaged var transcriptLineCount: Int64
    @NSManaged var previewText: String?
    @NSManaged var workspace: WorkspaceEntity?
}
