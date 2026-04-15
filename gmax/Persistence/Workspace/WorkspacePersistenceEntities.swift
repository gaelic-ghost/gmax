/*
 WorkspacePersistenceEntities defines the Core Data managed object surface for
 workspace persistence. These entities model the stored workspace list, pane
 trees, saved workspace snapshots, and per-pane session snapshot payloads used
 by the workspace persistence controller.
 */

import CoreData
import Foundation

enum PaneNodeKind: String {
	case leaf
	case split
}

enum SnapshotPersistenceError: Error {
	case missingSessionSnapshot(sessionID: UUID)
}

@objc(WorkspaceEntity)
final class WorkspaceEntity: NSManagedObject {
	@NSManaged var id: UUID
	@NSManaged var title: String
	@NSManaged var sortOrder: Int64
	@NSManaged var rootNode: PaneNodeEntity?
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

@objc(WorkspaceSnapshotEntity)
final class WorkspaceSnapshotEntity: NSManagedObject {
	@NSManaged var id: UUID
	@NSManaged var sourceWorkspaceID: UUID?
	@NSManaged var title: String
	@NSManaged var createdAt: Date
	@NSManaged var updatedAt: Date
	@NSManaged var lastOpenedAt: Date?
	@NSManaged var isPinned: Bool
	@NSManaged var notes: String?
	@NSManaged var previewText: String?
	@NSManaged var searchText: String?
	@NSManaged var rootNode: PaneSnapshotNodeEntity?
	@NSManaged var sessionSnapshots: NSSet?
}

@objc(PaneSnapshotNodeEntity)
final class PaneSnapshotNodeEntity: NSManagedObject {
	@NSManaged var id: UUID
	@NSManaged var kind: String
	@NSManaged var sessionSnapshotID: UUID?
	@NSManaged var axis: String?
	@NSManaged var fraction: Double
	@NSManaged var workspaceRoot: WorkspaceSnapshotEntity?
	@NSManaged var firstChild: PaneSnapshotNodeEntity?
	@NSManaged var firstParent: PaneSnapshotNodeEntity?
	@NSManaged var secondChild: PaneSnapshotNodeEntity?
	@NSManaged var secondParent: PaneSnapshotNodeEntity?
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
	@NSManaged var snapshot: WorkspaceSnapshotEntity?
}
