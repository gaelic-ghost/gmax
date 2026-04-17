/*
 WorkspacePersistenceController+LegacyCoreData defines the retired snapshot
 graph that still needs to exist inside the managed object model so the current
 store can ingest older databases before the compatibility layer is removed.
 */

import CoreData

extension WorkspacePersistenceController {
	static func makeLegacyManagedObjectEntities(
		paneSessionSnapshotEntity: NSEntityDescription
	) -> [NSEntityDescription] {
		let workspaceSnapshotEntity = NSEntityDescription()
		workspaceSnapshotEntity.name = "WorkspaceSnapshotEntity"
		workspaceSnapshotEntity.managedObjectClassName = NSStringFromClass(WorkspaceSnapshotEntity.self)

		let paneSnapshotNodeEntity = NSEntityDescription()
		paneSnapshotNodeEntity.name = "PaneSnapshotNodeEntity"
		paneSnapshotNodeEntity.managedObjectClassName = NSStringFromClass(PaneSnapshotNodeEntity.self)

		let workspaceSnapshotID = attribute(name: "id", type: .UUIDAttributeType)
		let workspaceSnapshotSourceWorkspaceID = attribute(name: "sourceWorkspaceID", type: .UUIDAttributeType, isOptional: true)
		let workspaceSnapshotTitle = attribute(name: "title", type: .stringAttributeType)
		let workspaceSnapshotCreatedAt = attribute(name: "createdAt", type: .dateAttributeType)
		let workspaceSnapshotUpdatedAt = attribute(name: "updatedAt", type: .dateAttributeType)
		let workspaceSnapshotLastOpenedAt = attribute(name: "lastOpenedAt", type: .dateAttributeType, isOptional: true)
		let workspaceSnapshotPinned = attribute(name: "isPinned", type: .booleanAttributeType)
		let workspaceSnapshotNotes = attribute(name: "notes", type: .stringAttributeType, isOptional: true)
		let workspaceSnapshotPreviewText = attribute(name: "previewText", type: .stringAttributeType, isOptional: true)
		let workspaceSnapshotSearchText = attribute(name: "searchText", type: .stringAttributeType, isOptional: true)

		let snapshotNodeID = attribute(name: "id", type: .UUIDAttributeType)
		let snapshotNodeKind = attribute(name: "kind", type: .stringAttributeType)
		let snapshotNodeSessionSnapshotID = attribute(name: "sessionSnapshotID", type: .UUIDAttributeType, isOptional: true)
		let snapshotNodeAxis = attribute(name: "axis", type: .stringAttributeType, isOptional: true)
		let snapshotNodeFraction = attribute(name: "fraction", type: .doubleAttributeType)

		let workspaceSnapshotRootNode = NSRelationshipDescription()
		workspaceSnapshotRootNode.name = "rootNode"
		workspaceSnapshotRootNode.destinationEntity = paneSnapshotNodeEntity
		workspaceSnapshotRootNode.minCount = 0
		workspaceSnapshotRootNode.maxCount = 1
		workspaceSnapshotRootNode.deleteRule = .cascadeDeleteRule

		let snapshotNodeWorkspaceRoot = NSRelationshipDescription()
		snapshotNodeWorkspaceRoot.name = "workspaceRoot"
		snapshotNodeWorkspaceRoot.destinationEntity = workspaceSnapshotEntity
		snapshotNodeWorkspaceRoot.minCount = 0
		snapshotNodeWorkspaceRoot.maxCount = 1
		snapshotNodeWorkspaceRoot.deleteRule = .nullifyDeleteRule

		workspaceSnapshotRootNode.inverseRelationship = snapshotNodeWorkspaceRoot
		snapshotNodeWorkspaceRoot.inverseRelationship = workspaceSnapshotRootNode

		let snapshotFirstChild = NSRelationshipDescription()
		snapshotFirstChild.name = "firstChild"
		snapshotFirstChild.destinationEntity = paneSnapshotNodeEntity
		snapshotFirstChild.minCount = 0
		snapshotFirstChild.maxCount = 1
		snapshotFirstChild.deleteRule = .cascadeDeleteRule

		let snapshotFirstParent = NSRelationshipDescription()
		snapshotFirstParent.name = "firstParent"
		snapshotFirstParent.destinationEntity = paneSnapshotNodeEntity
		snapshotFirstParent.minCount = 0
		snapshotFirstParent.maxCount = 1
		snapshotFirstParent.deleteRule = .nullifyDeleteRule

		snapshotFirstChild.inverseRelationship = snapshotFirstParent
		snapshotFirstParent.inverseRelationship = snapshotFirstChild

		let snapshotSecondChild = NSRelationshipDescription()
		snapshotSecondChild.name = "secondChild"
		snapshotSecondChild.destinationEntity = paneSnapshotNodeEntity
		snapshotSecondChild.minCount = 0
		snapshotSecondChild.maxCount = 1
		snapshotSecondChild.deleteRule = .cascadeDeleteRule

		let snapshotSecondParent = NSRelationshipDescription()
		snapshotSecondParent.name = "secondParent"
		snapshotSecondParent.destinationEntity = paneSnapshotNodeEntity
		snapshotSecondParent.minCount = 0
		snapshotSecondParent.maxCount = 1
		snapshotSecondParent.deleteRule = .nullifyDeleteRule

		snapshotSecondChild.inverseRelationship = snapshotSecondParent
		snapshotSecondParent.inverseRelationship = snapshotSecondChild

		let workspaceSnapshotSessionSnapshots = NSRelationshipDescription()
		workspaceSnapshotSessionSnapshots.name = "sessionSnapshots"
		workspaceSnapshotSessionSnapshots.destinationEntity = paneSessionSnapshotEntity
		workspaceSnapshotSessionSnapshots.minCount = 0
		workspaceSnapshotSessionSnapshots.maxCount = 0
		workspaceSnapshotSessionSnapshots.isOptional = true
		workspaceSnapshotSessionSnapshots.isOrdered = false
		workspaceSnapshotSessionSnapshots.deleteRule = .cascadeDeleteRule

		let paneSessionSnapshotWorkspaceSnapshot = NSRelationshipDescription()
		paneSessionSnapshotWorkspaceSnapshot.name = "snapshot"
		paneSessionSnapshotWorkspaceSnapshot.destinationEntity = workspaceSnapshotEntity
		paneSessionSnapshotWorkspaceSnapshot.minCount = 0
		paneSessionSnapshotWorkspaceSnapshot.maxCount = 1
		paneSessionSnapshotWorkspaceSnapshot.deleteRule = .nullifyDeleteRule

		workspaceSnapshotSessionSnapshots.inverseRelationship = paneSessionSnapshotWorkspaceSnapshot
		paneSessionSnapshotWorkspaceSnapshot.inverseRelationship = workspaceSnapshotSessionSnapshots

		workspaceSnapshotEntity.properties = [
			workspaceSnapshotID,
			workspaceSnapshotSourceWorkspaceID,
			workspaceSnapshotTitle,
			workspaceSnapshotCreatedAt,
			workspaceSnapshotUpdatedAt,
			workspaceSnapshotLastOpenedAt,
			workspaceSnapshotPinned,
			workspaceSnapshotNotes,
			workspaceSnapshotPreviewText,
			workspaceSnapshotSearchText,
			workspaceSnapshotRootNode,
			workspaceSnapshotSessionSnapshots,
		]
		paneSnapshotNodeEntity.properties = [
			snapshotNodeID,
			snapshotNodeKind,
			snapshotNodeSessionSnapshotID,
			snapshotNodeAxis,
			snapshotNodeFraction,
			snapshotNodeWorkspaceRoot,
			snapshotFirstChild,
			snapshotFirstParent,
			snapshotSecondChild,
			snapshotSecondParent,
		]

		paneSessionSnapshotEntity.properties.append(paneSessionSnapshotWorkspaceSnapshot)

		return [workspaceSnapshotEntity, paneSnapshotNodeEntity]
	}
}
