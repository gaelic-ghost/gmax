/*
 WorkspacePersistenceController+CoreData owns the storage engine setup.
 It defines where the workspace store lives on disk, constructs the Core Data
 container and managed object model, and handles store loading plus the
 in-memory fallback path when the disk-backed store is unavailable.
 */

import CoreData
import Foundation
import OSLog

extension WorkspacePersistenceController {
    nonisolated static func storeDirectoryURL() -> URL {
        let fileManager = FileManager.default
        let directoryURL = URL.applicationSupportDirectory
            .appending(path: "gmax-exploration", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            Logger.persistence
                .error("The app could not create the Application Support directory for workspace persistence. The SQLite store may fail to open on this launch. Directory: \(directoryURL.path, privacy: .public). Error: \(String(describing: error), privacy: .public)")
        }
        return directoryURL
    }

    nonisolated static func storeURL(for profile: WorkspacePersistenceProfile = .appDefault()) -> URL {
        precondition(
            !profile.usesInMemoryStore,
            "The in-memory workspace persistence profile does not have an on-disk store URL.",
        )
        return storeDirectoryURL().appendingPathComponent(profile.storeFileName ?? "WorkspaceStore.sqlite")
    }

    nonisolated static func storeCleanupURLs(for profile: WorkspacePersistenceProfile = .appDefault()) -> [URL] {
        guard !profile.usesInMemoryStore else {
            return []
        }

        let storeURL = storeURL(for: profile)
        return [storeURL, storeURL.appendingPathExtension("shm"), storeURL.appendingPathExtension("wal")]
    }

    static func makePersistentContainer(profile: WorkspacePersistenceProfile) -> NSPersistentContainer {
        let model = makeManagedObjectModel()
        let description = makeStoreDescription(for: profile)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        let primaryContainer = makeContainer(
            model: model,
            description: description,
            contextName: profile.contextName,
        )

        Logger.persistence.notice(
            "Configured workspace persistence using the \(profile.displayName, privacy: .public).",
        )

        if loadPersistentStores(for: primaryContainer, profile: profile) {
            return primaryContainer
        }

        Logger.persistence.error("Core Data could not open the on-disk workspace store, so the app is falling back to an in-memory store for this launch. Workspace changes will remain live, but they will not survive quitting the app until the disk-backed store loads successfully again.")

        let fallbackContainer = makeContainer(
            model: model,
            description: {
                let description = NSPersistentStoreDescription()
                description.type = NSInMemoryStoreType
                return description
            }(),
            contextName: WorkspacePersistenceProfile.inMemory.contextName,
        )

        guard loadPersistentStores(for: fallbackContainer, profile: .inMemory) else {
            fatalError("Core Data could not load either the disk-backed workspace store or the in-memory fallback store. The app cannot continue without a managed object context.")
        }

        return fallbackContainer
    }

    static func makeStoreDescription(for profile: WorkspacePersistenceProfile) -> NSPersistentStoreDescription {
        if profile.usesInMemoryStore {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            return description
        }

        return NSPersistentStoreDescription(url: storeURL(for: profile))
    }

    static func makeContainer(
        model: NSManagedObjectModel,
        description: NSPersistentStoreDescription,
        contextName: String,
    ) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "WorkspaceStore", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        container.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = contextName
        return container
    }

    static func loadPersistentStores(
        for container: NSPersistentContainer,
        profile: WorkspacePersistenceProfile,
    ) -> Bool {
        var loadError: Error?
        var loadedStoreDescription: NSPersistentStoreDescription?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { description, error in
            loadedStoreDescription = description
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let loadError {
            let requestedStoreLocation = if profile.usesInMemoryStore {
                "in-memory"
            } else {
                storeURL(for: profile).path
            }
            let resolvedStoreLocation = loadedStoreDescription?.url?.path ?? requestedStoreLocation
            Logger.persistence.error(
                "Core Data could not load the \(profile.displayName, privacy: .public). The requested workspace store will remain unavailable for this launch, and the app may fall back to a different store profile if one is configured. Requested store location: \(requestedStoreLocation, privacy: .public). Resolved store location: \(resolvedStoreLocation, privacy: .public). Error: \(String(describing: loadError), privacy: .public)",
            )
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

        let workspacePlacementEntity = NSEntityDescription()
        workspacePlacementEntity.name = "WorkspacePlacementEntity"
        workspacePlacementEntity.managedObjectClassName = NSStringFromClass(WorkspacePlacementEntity.self)

        let workspaceWindowStateEntity = NSEntityDescription()
        workspaceWindowStateEntity.name = "WorkspaceWindowStateEntity"
        workspaceWindowStateEntity.managedObjectClassName = NSStringFromClass(WorkspaceWindowStateEntity.self)

        let paneSessionSnapshotEntity = NSEntityDescription()
        paneSessionSnapshotEntity.name = "PaneSessionSnapshotEntity"
        paneSessionSnapshotEntity.managedObjectClassName = NSStringFromClass(PaneSessionSnapshotEntity.self)

        let workspaceID = attribute(name: "id", type: .UUIDAttributeType)
        let workspaceTitle = attribute(name: "title", type: .stringAttributeType)
        let migrationDefaultDate = Date()

        let workspaceCreatedAt = attribute(
            name: "createdAt",
            type: .dateAttributeType,
            defaultValue: migrationDefaultDate,
        )
        let workspaceUpdatedAt = attribute(
            name: "updatedAt",
            type: .dateAttributeType,
            defaultValue: migrationDefaultDate,
        )
        let workspaceNotes = attribute(name: "notes", type: .stringAttributeType, isOptional: true)
        let workspacePreviewText = attribute(name: "previewText", type: .stringAttributeType, isOptional: true)
        let workspaceSearchText = attribute(name: "searchText", type: .stringAttributeType, isOptional: true)
        let sortOrder = attribute(name: "sortOrder", type: .integer64AttributeType)

        let nodeID = attribute(name: "id", type: .UUIDAttributeType)
        let nodeKind = attribute(name: "kind", type: .stringAttributeType)
        let nodeSessionID = attribute(name: "sessionID", type: .UUIDAttributeType, isOptional: true)
        let nodeAxis = attribute(name: "axis", type: .stringAttributeType, isOptional: true)
        let nodeFraction = attribute(name: "fraction", type: .doubleAttributeType)

        let placementID = attribute(name: "id", type: .UUIDAttributeType)
        let placementRole = attribute(name: "role", type: .stringAttributeType)
        let placementWindowID = attribute(name: "windowID", type: .UUIDAttributeType, isOptional: true)
        let placementSortOrder = attribute(name: "sortOrder", type: .integer64AttributeType, defaultValue: 0)
        let placementRestoreSortOrder = attribute(name: "restoreSortOrder", type: .integer64AttributeType, defaultValue: 0)
        let placementCreatedAt = attribute(
            name: "createdAt",
            type: .dateAttributeType,
            defaultValue: migrationDefaultDate,
        )
        let placementUpdatedAt = attribute(
            name: "updatedAt",
            type: .dateAttributeType,
            defaultValue: migrationDefaultDate,
        )
        let placementLastOpenedAt = attribute(name: "lastOpenedAt", type: .dateAttributeType, isOptional: true)
        let placementIsPinned = attribute(name: "isPinned", type: .booleanAttributeType, defaultValue: false)
        let placementTitle = attribute(name: "title", type: .stringAttributeType)
        let placementPreviewText = attribute(name: "previewText", type: .stringAttributeType, isOptional: true)
        let placementSearchText = attribute(name: "searchText", type: .stringAttributeType, isOptional: true)
        let placementPaneCount = attribute(name: "paneCount", type: .integer64AttributeType, defaultValue: 0)

        let windowStateWindowID = attribute(name: "windowID", type: .UUIDAttributeType)
        let windowStateSelectedWorkspaceID = attribute(name: "selectedWorkspaceID", type: .UUIDAttributeType, isOptional: true)
        let windowStateCreatedAt = attribute(
            name: "createdAt",
            type: .dateAttributeType,
            defaultValue: migrationDefaultDate,
        )
        let windowStateUpdatedAt = attribute(
            name: "updatedAt",
            type: .dateAttributeType,
            defaultValue: migrationDefaultDate,
        )

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

        let workspacePlacements = NSRelationshipDescription()
        workspacePlacements.name = "placements"
        workspacePlacements.destinationEntity = workspacePlacementEntity
        workspacePlacements.minCount = 0
        workspacePlacements.maxCount = 0
        workspacePlacements.isOptional = true
        workspacePlacements.isOrdered = false
        workspacePlacements.deleteRule = .nullifyDeleteRule

        let placementWorkspace = NSRelationshipDescription()
        placementWorkspace.name = "workspace"
        placementWorkspace.destinationEntity = workspaceEntity
        placementWorkspace.minCount = 0
        placementWorkspace.maxCount = 1
        placementWorkspace.deleteRule = .nullifyDeleteRule

        workspacePlacements.inverseRelationship = placementWorkspace
        placementWorkspace.inverseRelationship = workspacePlacements

        let workspaceSessionSnapshots = NSRelationshipDescription()
        workspaceSessionSnapshots.name = "sessionSnapshots"
        workspaceSessionSnapshots.destinationEntity = paneSessionSnapshotEntity
        workspaceSessionSnapshots.minCount = 0
        workspaceSessionSnapshots.maxCount = 0
        workspaceSessionSnapshots.isOptional = true
        workspaceSessionSnapshots.isOrdered = false
        workspaceSessionSnapshots.deleteRule = .cascadeDeleteRule

        let paneSessionSnapshotWorkspace = NSRelationshipDescription()
        paneSessionSnapshotWorkspace.name = "workspace"
        paneSessionSnapshotWorkspace.destinationEntity = workspaceEntity
        paneSessionSnapshotWorkspace.minCount = 0
        paneSessionSnapshotWorkspace.maxCount = 1
        paneSessionSnapshotWorkspace.deleteRule = .nullifyDeleteRule

        workspaceSessionSnapshots.inverseRelationship = paneSessionSnapshotWorkspace
        paneSessionSnapshotWorkspace.inverseRelationship = workspaceSessionSnapshots

        workspaceEntity.properties = [
            workspaceID,
            workspaceTitle,
            workspaceCreatedAt,
            workspaceUpdatedAt,
            workspaceNotes,
            workspacePreviewText,
            workspaceSearchText,
            sortOrder,
            workspaceRootNode,
            workspacePlacements,
            workspaceSessionSnapshots,
        ]
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
        workspacePlacementEntity.properties = [
            placementID,
            placementRole,
            placementWindowID,
            placementSortOrder,
            placementRestoreSortOrder,
            placementCreatedAt,
            placementUpdatedAt,
            placementLastOpenedAt,
            placementIsPinned,
            placementTitle,
            placementPreviewText,
            placementSearchText,
            placementPaneCount,
            placementWorkspace,
        ]

        workspaceWindowStateEntity.properties = [
            windowStateWindowID,
            windowStateSelectedWorkspaceID,
            windowStateCreatedAt,
            windowStateUpdatedAt,
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
            paneSessionSnapshotWorkspace,
        ]

        model.entities = [
            workspaceEntity,
            paneNodeEntity,
            workspacePlacementEntity,
            workspaceWindowStateEntity,
            paneSessionSnapshotEntity,
        ]
        return model
    }

    static func attribute(
        name: String,
        type: NSAttributeType,
        isOptional: Bool = false,
        defaultValue: Any? = nil,
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        return attribute
    }
}
