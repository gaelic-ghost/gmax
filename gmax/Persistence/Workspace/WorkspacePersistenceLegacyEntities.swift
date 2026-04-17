/*
 Legacy workspace persistence entities remain only to let the current payload
 plus placement store ingest older on-disk records during migration. No active
 runtime path should depend on these entities after migration completes.
 */

import CoreData
import Foundation

enum SnapshotPersistenceError: Error {
	case missingSessionSnapshot(sessionID: UUID)
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

extension PaneSessionSnapshotEntity {
	@NSManaged var snapshot: WorkspaceSnapshotEntity?
}
