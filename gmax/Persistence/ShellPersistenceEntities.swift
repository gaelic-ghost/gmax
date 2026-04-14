//
//  ShellPersistenceEntities.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import CoreData
import Foundation

enum PaneNodeKind: String {
	case leaf
	case split
}

enum SnapshotPersistenceError: Error {
	case missingSessionSnapshot(sessionID: UUID)
	case missingEncodedPayload(typeName: String)
}

@objc(WorkspaceEntity)
final class WorkspaceEntity: NSManagedObject {
	@NSManaged var id: UUID
	@NSManaged var title: String
	@NSManaged var focusedPaneID: UUID?
	@NSManaged var sortOrder: Int64
	@NSManaged var rootNode: PaneNodeEntity?
}

extension WorkspaceEntity {
	@nonobjc static func fetchRequest() -> NSFetchRequest<WorkspaceEntity> {
		NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
	}
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

extension PaneNodeEntity {
	@nonobjc static func fetchRequest() -> NSFetchRequest<PaneNodeEntity> {
		NSFetchRequest<PaneNodeEntity>(entityName: "PaneNodeEntity")
	}
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
	@NSManaged var focusedPaneID: UUID?
	@NSManaged var rootNode: PaneSnapshotNodeEntity?
	@NSManaged var sessionSnapshots: NSSet?
}

extension WorkspaceSnapshotEntity {
	@nonobjc static func fetchRequest() -> NSFetchRequest<WorkspaceSnapshotEntity> {
		NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
	}
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

extension PaneSnapshotNodeEntity {
	@nonobjc static func fetchRequest() -> NSFetchRequest<PaneSnapshotNodeEntity> {
		NSFetchRequest<PaneSnapshotNodeEntity>(entityName: "PaneSnapshotNodeEntity")
	}
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

extension PaneSessionSnapshotEntity {
	@nonobjc static func fetchRequest() -> NSFetchRequest<PaneSessionSnapshotEntity> {
		NSFetchRequest<PaneSessionSnapshotEntity>(entityName: "PaneSessionSnapshotEntity")
	}
}
