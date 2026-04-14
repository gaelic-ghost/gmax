//
//  ShellPersistenceController+CoreData.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import CoreData
import Foundation
import OSLog

extension ShellPersistenceController {
	static func storeURL() -> URL {
		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		let directoryURL = appSupportURL.appendingPathComponent("gmax-exploration", isDirectory: true)
		do {
			try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
		} catch {
			Logger.gmax(.persistence)
				.error("The app could not create the Application Support directory for shell persistence. The SQLite store may fail to open on this launch. Directory: \(directoryURL.path, privacy: .public). Error: \(String(describing: error), privacy: .public)")
		}
		return directoryURL.appendingPathComponent("ShellStore.sqlite")
	}

	static func makePersistentContainer(logger: Logger) -> NSPersistentContainer {
		let model = makeManagedObjectModel()
		let primaryContainer = makeContainer(
			model: model,
			description: persistentStoreDescription(),
			contextName: "ShellPersistence.viewContext"
		)

		if loadPersistentStores(for: primaryContainer, logger: logger) {
			return primaryContainer
		}

		logger.error("Core Data could not open the on-disk shell store, so the app is falling back to an in-memory store for this launch. Workspace changes will remain live, but they will not survive quitting the app until the disk-backed store loads successfully again.")

		let fallbackContainer = makeContainer(
			model: model,
			description: inMemoryStoreDescription(),
			contextName: "ShellPersistence.inMemoryViewContext"
		)

		guard loadPersistentStores(for: fallbackContainer, logger: logger) else {
			fatalError("Core Data could not load either the disk-backed shell store or the in-memory fallback store. The app cannot continue without a managed object context.")
		}

		return fallbackContainer
	}

	static func persistentStoreDescription() -> NSPersistentStoreDescription {
		let description = NSPersistentStoreDescription(url: storeURL())
		description.shouldMigrateStoreAutomatically = true
		description.shouldInferMappingModelAutomatically = true
		return description
	}

	static func inMemoryStoreDescription() -> NSPersistentStoreDescription {
		let description = NSPersistentStoreDescription()
		description.type = NSInMemoryStoreType
		return description
	}

	static func makeContainer(
		model: NSManagedObjectModel,
		description: NSPersistentStoreDescription,
		contextName: String
	) -> NSPersistentContainer {
		let container = NSPersistentContainer(name: "ShellStore", managedObjectModel: model)
		container.persistentStoreDescriptions = [description]
		container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
		container.viewContext.automaticallyMergesChangesFromParent = true
		container.viewContext.name = contextName
		return container
	}

	static func loadPersistentStores(
		for container: NSPersistentContainer,
		logger: Logger
	) -> Bool {
		var loadError: Error?
		let semaphore = DispatchSemaphore(value: 0)
		container.loadPersistentStores { _, error in
			loadError = error
			semaphore.signal()
		}
		semaphore.wait()

		if let loadError {
			logger.error("Core Data could not load a shell persistent store description. The store described by this container will remain unavailable for this launch. Error: \(String(describing: loadError), privacy: .public)")
			return false
		}

		return true
	}

	static func makeManagedObjectModel() -> NSManagedObjectModel {
		let model = NSManagedObjectModel()

		let workspaceEntity = NSEntityDescription()
		workspaceEntity.name = "WorkspaceEntity"
		workspaceEntity.managedObjectClassName = NSStringFromClass(WorkspaceEntity.self)

		let paneNodeEntity = NSEntityDescription()
		paneNodeEntity.name = "PaneNodeEntity"
		paneNodeEntity.managedObjectClassName = NSStringFromClass(PaneNodeEntity.self)

		let workspaceSnapshotEntity = NSEntityDescription()
		workspaceSnapshotEntity.name = "WorkspaceSnapshotEntity"
		workspaceSnapshotEntity.managedObjectClassName = NSStringFromClass(WorkspaceSnapshotEntity.self)

		let paneSnapshotNodeEntity = NSEntityDescription()
		paneSnapshotNodeEntity.name = "PaneSnapshotNodeEntity"
		paneSnapshotNodeEntity.managedObjectClassName = NSStringFromClass(PaneSnapshotNodeEntity.self)

		let paneSessionSnapshotEntity = NSEntityDescription()
		paneSessionSnapshotEntity.name = "PaneSessionSnapshotEntity"
		paneSessionSnapshotEntity.managedObjectClassName = NSStringFromClass(PaneSessionSnapshotEntity.self)

		let workspaceID = attribute(name: "id", type: .UUIDAttributeType)
		let workspaceTitle = attribute(name: "title", type: .stringAttributeType)
		let focusedPaneID = attribute(name: "focusedPaneID", type: .UUIDAttributeType, isOptional: true)
		let sortOrder = attribute(name: "sortOrder", type: .integer64AttributeType)

		let nodeID = attribute(name: "id", type: .UUIDAttributeType)
		let nodeKind = attribute(name: "kind", type: .stringAttributeType)
		let nodeSessionID = attribute(name: "sessionID", type: .UUIDAttributeType, isOptional: true)
		let nodeAxis = attribute(name: "axis", type: .stringAttributeType, isOptional: true)
		let nodeFraction = attribute(name: "fraction", type: .doubleAttributeType)

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
		let workspaceSnapshotFocusedPaneID = attribute(name: "focusedPaneID", type: .UUIDAttributeType, isOptional: true)

		let snapshotNodeID = attribute(name: "id", type: .UUIDAttributeType)
		let snapshotNodeKind = attribute(name: "kind", type: .stringAttributeType)
		let snapshotNodeSessionSnapshotID = attribute(name: "sessionSnapshotID", type: .UUIDAttributeType, isOptional: true)
		let snapshotNodeAxis = attribute(name: "axis", type: .stringAttributeType, isOptional: true)
		let snapshotNodeFraction = attribute(name: "fraction", type: .doubleAttributeType)

		let paneSessionSnapshotID = attribute(name: "id", type: .UUIDAttributeType)
		let paneSessionSnapshotExecutable = attribute(name: "executable", type: .stringAttributeType)
		let paneSessionSnapshotArgumentsData = attribute(name: "argumentsData", type: .binaryDataAttributeType)
		let paneSessionSnapshotEnvironmentData = attribute(name: "environmentData", type: .binaryDataAttributeType, isOptional: true)
		let paneSessionSnapshotCurrentDirectory = attribute(name: "currentDirectory", type: .stringAttributeType, isOptional: true)
		let paneSessionSnapshotTitle = attribute(name: "title", type: .stringAttributeType)
		let paneSessionSnapshotTranscript = attribute(name: "transcript", type: .stringAttributeType, isOptional: true)
		let paneSessionSnapshotTranscriptByteCount = attribute(name: "transcriptByteCount", type: .integer64AttributeType)
		let paneSessionSnapshotTranscriptLineCount = attribute(name: "transcriptLineCount", type: .integer64AttributeType)
		let paneSessionSnapshotPreviewText = attribute(name: "previewText", type: .stringAttributeType, isOptional: true)

		let workspaceRootNode = NSRelationshipDescription()
		workspaceRootNode.name = "rootNode"
		workspaceRootNode.destinationEntity = paneNodeEntity
		workspaceRootNode.minCount = 0
		workspaceRootNode.maxCount = 1
		workspaceRootNode.deleteRule = .cascadeDeleteRule

		let nodeWorkspaceRoot = NSRelationshipDescription()
		nodeWorkspaceRoot.name = "workspaceRoot"
		nodeWorkspaceRoot.destinationEntity = workspaceEntity
		nodeWorkspaceRoot.minCount = 0
		nodeWorkspaceRoot.maxCount = 1
		nodeWorkspaceRoot.deleteRule = .nullifyDeleteRule

		workspaceRootNode.inverseRelationship = nodeWorkspaceRoot
		nodeWorkspaceRoot.inverseRelationship = workspaceRootNode

		let firstChild = NSRelationshipDescription()
		firstChild.name = "firstChild"
		firstChild.destinationEntity = paneNodeEntity
		firstChild.minCount = 0
		firstChild.maxCount = 1
		firstChild.deleteRule = .cascadeDeleteRule

		let firstParent = NSRelationshipDescription()
		firstParent.name = "firstParent"
		firstParent.destinationEntity = paneNodeEntity
		firstParent.minCount = 0
		firstParent.maxCount = 1
		firstParent.deleteRule = .nullifyDeleteRule

		firstChild.inverseRelationship = firstParent
		firstParent.inverseRelationship = firstChild

		let secondChild = NSRelationshipDescription()
		secondChild.name = "secondChild"
		secondChild.destinationEntity = paneNodeEntity
		secondChild.minCount = 0
		secondChild.maxCount = 1
		secondChild.deleteRule = .cascadeDeleteRule

		let secondParent = NSRelationshipDescription()
		secondParent.name = "secondParent"
		secondParent.destinationEntity = paneNodeEntity
		secondParent.minCount = 0
		secondParent.maxCount = 1
		secondParent.deleteRule = .nullifyDeleteRule

		secondChild.inverseRelationship = secondParent
		secondParent.inverseRelationship = secondChild

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

		workspaceEntity.properties = [workspaceID, workspaceTitle, focusedPaneID, sortOrder, workspaceRootNode]
		paneNodeEntity.properties = [
			nodeID,
			nodeKind,
			nodeSessionID,
			nodeAxis,
			nodeFraction,
			nodeWorkspaceRoot,
			firstChild,
			firstParent,
			secondChild,
			secondParent,
		]

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
			workspaceSnapshotFocusedPaneID,
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
		paneSessionSnapshotEntity.properties = [
			paneSessionSnapshotID,
			paneSessionSnapshotExecutable,
			paneSessionSnapshotArgumentsData,
			paneSessionSnapshotEnvironmentData,
			paneSessionSnapshotCurrentDirectory,
			paneSessionSnapshotTitle,
			paneSessionSnapshotTranscript,
			paneSessionSnapshotTranscriptByteCount,
			paneSessionSnapshotTranscriptLineCount,
			paneSessionSnapshotPreviewText,
			paneSessionSnapshotWorkspaceSnapshot,
		]

		model.entities = [workspaceEntity, paneNodeEntity, workspaceSnapshotEntity, paneSnapshotNodeEntity, paneSessionSnapshotEntity]
		return model
	}

	static func attribute(
		name: String,
		type: NSAttributeType,
		isOptional: Bool = false
	) -> NSAttributeDescription {
		let attribute = NSAttributeDescription()
		attribute.name = name
		attribute.attributeType = type
		attribute.isOptional = isOptional
		return attribute
	}
}
