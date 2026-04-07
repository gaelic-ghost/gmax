//
//  ShellPersistenceController.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import CoreData
import Foundation
import OSLog

@MainActor
final class ShellPersistenceController {
	static let shared = ShellPersistenceController()

	private let logger = Logger(subsystem: "com.galewilliams.gmax-exploration", category: "ShellPersistence")
	private let container: NSPersistentContainer

	private init() {
		self.container = Self.makePersistentContainer(logger: logger)
	}

	func loadWorkspaces() -> [Workspace] {
		let context = container.viewContext
		let request = WorkspaceEntity.fetchRequest()
		request.sortDescriptors = [NSSortDescriptor(key: #keyPath(WorkspaceEntity.sortOrder), ascending: true)]

		do {
			return try context.fetch(request).map { workspaceEntity in
				Workspace(
					id: WorkspaceID(rawValue: workspaceEntity.id),
					title: workspaceEntity.title,
					root: Self.decodeNode(workspaceEntity.rootNode, logger: logger),
					focusedPaneID: workspaceEntity.focusedPaneID.map(PaneID.init(rawValue:))
				)
			}
		} catch {
			logger.error("Core Data failed to load saved workspaces. The app will continue with default workspace state. Error: \(String(describing: error), privacy: .public)")
			return []
		}
	}

	func save(workspaces: [Workspace]) {
		let context = container.viewContext
		context.performAndWait {
			do {
				let existingWorkspaces = try context.fetch(WorkspaceEntity.fetchRequest())
				let existingNodes = try context.fetch(PaneNodeEntity.fetchRequest())

				var workspacesByID = Dictionary(uniqueKeysWithValues: existingWorkspaces.map { ($0.id, $0) })
				var nodesByID = Dictionary(uniqueKeysWithValues: existingNodes.map { ($0.id, $0) })
				var retainedWorkspaceIDs: Set<UUID> = []
				var retainedNodeIDs: Set<UUID> = []

				for (sortOrder, workspace) in workspaces.enumerated() {
					let workspaceEntity = workspacesByID.removeValue(forKey: workspace.id.rawValue)
					?? WorkspaceEntity(context: context)
					workspaceEntity.id = workspace.id.rawValue
					workspaceEntity.title = workspace.title
					workspaceEntity.focusedPaneID = workspace.focusedPaneID?.rawValue
					workspaceEntity.sortOrder = Int64(sortOrder)
					workspaceEntity.rootNode = Self.syncNode(
						workspace.root,
						context: context,
						nodesByID: &nodesByID,
						retainedNodeIDs: &retainedNodeIDs
					)
					retainedWorkspaceIDs.insert(workspace.id.rawValue)
				}

				for orphanedWorkspace in workspacesByID.values where !retainedWorkspaceIDs.contains(orphanedWorkspace.id) {
					context.delete(orphanedWorkspace)
				}

				for orphanedNode in nodesByID.values where !retainedNodeIDs.contains(orphanedNode.id) {
					context.delete(orphanedNode)
				}

				if context.hasChanges {
					try context.save()
				}
			} catch {
				logger.error("Core Data failed to save shell workspace state. The current session remains live, but the last change was not persisted. Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
	}

	private nonisolated static func syncNode(
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

	private static func decodeNode(_ nodeEntity: PaneNodeEntity?, logger: Logger) -> PaneNode? {
		guard let nodeEntity else {
			return nil
		}

		switch PaneNodeKind(rawValue: nodeEntity.kind) {
			case .leaf:
				guard let sessionID = nodeEntity.sessionID else {
					logger.error("A persisted leaf node is missing its session identifier. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
					logger.error("A persisted split node is missing or has an invalid axis. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				guard let first = decodeNode(nodeEntity.firstChild, logger: logger),
					  let second = decodeNode(nodeEntity.secondChild, logger: logger)
				else {
					logger.error("A persisted split node is missing one or both child nodes. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
				logger.error("A persisted pane node has an unknown kind value. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
				return nil
		}
	}

	private static func storeURL() -> URL {
		let fileManager = FileManager.default
		let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
		let directoryURL = appSupportURL.appendingPathComponent("gmax-exploration", isDirectory: true)
		do {
			try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
		} catch {
			Logger(subsystem: "com.galewilliams.gmax-exploration", category: "ShellPersistence")
				.error("Failed to create the Application Support directory for shell persistence. The store may fail to load. Directory: \(directoryURL.path, privacy: .public). Error: \(String(describing: error), privacy: .public)")
		}
		return directoryURL.appendingPathComponent("ShellStore.sqlite")
	}

	private static func makePersistentContainer(logger: Logger) -> NSPersistentContainer {
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

	private static func persistentStoreDescription() -> NSPersistentStoreDescription {
		let description = NSPersistentStoreDescription(url: storeURL())
		description.shouldMigrateStoreAutomatically = true
		description.shouldInferMappingModelAutomatically = true
		return description
	}

	private static func inMemoryStoreDescription() -> NSPersistentStoreDescription {
		let description = NSPersistentStoreDescription()
		description.type = NSInMemoryStoreType
		return description
	}

	private static func makeContainer(
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

	private static func loadPersistentStores(
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
			logger.error("Core Data failed to load a shell persistent store description. Error: \(String(describing: loadError), privacy: .public)")
			return false
		}

		return true
	}

	private static func makeManagedObjectModel() -> NSManagedObjectModel {
		let model = NSManagedObjectModel()

		let workspaceEntity = NSEntityDescription()
		workspaceEntity.name = "WorkspaceEntity"
		workspaceEntity.managedObjectClassName = NSStringFromClass(WorkspaceEntity.self)

		let paneNodeEntity = NSEntityDescription()
		paneNodeEntity.name = "PaneNodeEntity"
		paneNodeEntity.managedObjectClassName = NSStringFromClass(PaneNodeEntity.self)

		let workspaceID = attribute(name: "id", type: .UUIDAttributeType)
		let workspaceTitle = attribute(name: "title", type: .stringAttributeType)
		let focusedPaneID = attribute(name: "focusedPaneID", type: .UUIDAttributeType, isOptional: true)
		let sortOrder = attribute(name: "sortOrder", type: .integer64AttributeType)

		let nodeID = attribute(name: "id", type: .UUIDAttributeType)
		let nodeKind = attribute(name: "kind", type: .stringAttributeType)
		let nodeSessionID = attribute(name: "sessionID", type: .UUIDAttributeType, isOptional: true)
		let nodeAxis = attribute(name: "axis", type: .stringAttributeType, isOptional: true)
		let nodeFraction = attribute(name: "fraction", type: .doubleAttributeType)

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

		model.entities = [workspaceEntity, paneNodeEntity]
		return model
	}

	private static func attribute(
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

private enum PaneNodeKind: String {
	case leaf
	case split
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
