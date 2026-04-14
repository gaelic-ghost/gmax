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
				return try context.fetch(request).compactMap { workspaceEntity in
					let workspace = Workspace(
						id: WorkspaceID(rawValue: workspaceEntity.id),
						title: workspaceEntity.title,
						root: Self.decodeNode(workspaceEntity.rootNode, logger: logger),
						focusedPaneID: workspaceEntity.focusedPaneID.map(PaneID.init(rawValue:))
					)

					return Self.normalizedWorkspace(workspace, logger: logger)
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

	func createWorkspaceSnapshot(
		from workspace: Workspace,
		sessions: TerminalSessionRegistry,
		transcriptsBySessionID: [TerminalSessionID: String] = [:],
		notes: String? = nil,
		isPinned: Bool? = nil
	) -> SavedWorkspaceSnapshotSummary? {
		let context = container.viewContext
		var createdSummary: SavedWorkspaceSnapshotSummary?
		let now = Date()
		let pendingPaneSnapshots: [PendingPaneSessionSnapshot] = workspace.paneLeaves.map { leaf in
			let session = sessions.ensureSession(id: leaf.sessionID)
			let launchConfiguration = launchConfigurationForSnapshot(from: session)
			let transcript = transcriptsBySessionID[leaf.sessionID]
			let previewText = Self.previewText(for: transcript)
			return PendingPaneSessionSnapshot(
				sessionID: leaf.sessionID,
				title: session.title,
				launchConfiguration: launchConfiguration,
				argumentsData: try? Self.encode(launchConfiguration.arguments),
				environmentData: try? Self.encode(launchConfiguration.environment),
				transcript: transcript,
				transcriptByteCount: transcript?.utf8.count ?? 0,
				transcriptLineCount: Self.lineCount(for: transcript),
				previewText: previewText
			)
		}

		var searchComponents: [String] = [workspace.title]
		if let notes, !notes.isEmpty {
			searchComponents.append(notes)
		}
		for snapshot in pendingPaneSnapshots {
			if let previewText = snapshot.previewText, !previewText.isEmpty {
				searchComponents.append(previewText)
			}
			if let transcript = snapshot.transcript, !transcript.isEmpty {
				searchComponents.append(transcript)
			}
		}

		let flattenedSearchText = normalizedSearchText(from: searchComponents)
		let previewText = pendingPaneSnapshots.lazy.compactMap(\.previewText).first

		context.performAndWait {
			do {
					let snapshotEntity = try Self.existingSnapshotEntity(
						forSourceWorkspaceID: workspace.id,
						in: context
					) ?? WorkspaceSnapshotEntity(context: context)
				let snapshotID = snapshotEntity.sourceWorkspaceID == workspace.id.rawValue
					? WorkspaceSnapshotID(rawValue: snapshotEntity.id)
					: WorkspaceSnapshotID()
					if snapshotEntity.sourceWorkspaceID != workspace.id.rawValue {
						snapshotEntity.id = snapshotID.rawValue
						snapshotEntity.createdAt = now
						snapshotEntity.lastOpenedAt = nil
						snapshotEntity.isPinned = false
					} else {
						Self.deleteExistingSnapshotContents(from: snapshotEntity, in: context)
					}

				snapshotEntity.sourceWorkspaceID = workspace.id.rawValue
				snapshotEntity.title = workspace.title
				snapshotEntity.updatedAt = now
				if let isPinned {
					snapshotEntity.isPinned = isPinned
				}
				if let notes {
					snapshotEntity.notes = notes
				}
				snapshotEntity.focusedPaneID = workspace.focusedPaneID?.rawValue

				var sessionSnapshotsByID: [UUID: PaneSessionSnapshotEntity] = [:]
				for pendingPaneSnapshot in pendingPaneSnapshots {
					let sessionSnapshotEntity = PaneSessionSnapshotEntity(context: context)
					sessionSnapshotEntity.id = pendingPaneSnapshot.sessionID.rawValue
					sessionSnapshotEntity.executable = pendingPaneSnapshot.launchConfiguration.executable
					sessionSnapshotEntity.argumentsData = pendingPaneSnapshot.argumentsData
					sessionSnapshotEntity.environmentData = pendingPaneSnapshot.environmentData
					sessionSnapshotEntity.currentDirectory = pendingPaneSnapshot.launchConfiguration.currentDirectory
					sessionSnapshotEntity.title = pendingPaneSnapshot.title
					sessionSnapshotEntity.transcript = pendingPaneSnapshot.transcript
					sessionSnapshotEntity.transcriptByteCount = Int64(pendingPaneSnapshot.transcriptByteCount)
					sessionSnapshotEntity.transcriptLineCount = Int64(pendingPaneSnapshot.transcriptLineCount)
					sessionSnapshotEntity.previewText = pendingPaneSnapshot.previewText
					sessionSnapshotEntity.snapshot = snapshotEntity
					sessionSnapshotsByID[sessionSnapshotEntity.id] = sessionSnapshotEntity
				}

				snapshotEntity.rootNode = try Self.syncSnapshotNode(
					workspace.root,
					context: context,
					sessionSnapshotsByID: sessionSnapshotsByID
				)
				snapshotEntity.previewText = previewText
				snapshotEntity.searchText = flattenedSearchText

				try context.save()
				createdSummary = SavedWorkspaceSnapshotSummary(
					id: snapshotID,
					title: workspace.title,
					createdAt: snapshotEntity.createdAt,
					updatedAt: now,
					lastOpenedAt: snapshotEntity.lastOpenedAt,
					isPinned: snapshotEntity.isPinned,
					previewText: previewText,
					paneCount: workspace.paneCount
				)
			} catch {
				logger.error("Core Data failed to create a saved workspace snapshot. The live workspace remains open, but the snapshot was not written. Workspace title: \(workspace.title, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}

		return createdSummary
	}

	private nonisolated static func existingSnapshotEntity(
		forSourceWorkspaceID workspaceID: WorkspaceID,
		in context: NSManagedObjectContext
	) throws -> WorkspaceSnapshotEntity? {
		let request = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
		request.fetchLimit = 1
		request.predicate = NSPredicate(format: "sourceWorkspaceID == %@", workspaceID.rawValue as CVarArg)
		return try context.fetch(request).first
	}

	private nonisolated static func deleteExistingSnapshotContents(
		from snapshotEntity: WorkspaceSnapshotEntity,
		in context: NSManagedObjectContext
	) {
		if let existingRootNode = snapshotEntity.rootNode {
			context.delete(existingRootNode)
		}

		let existingSessionSnapshots = snapshotEntity.sessionSnapshots as? Set<PaneSessionSnapshotEntity> ?? []
		for existingSessionSnapshot in existingSessionSnapshots {
			context.delete(existingSessionSnapshot)
		}

		snapshotEntity.rootNode = nil
		snapshotEntity.sessionSnapshots = nil
	}

	func listWorkspaceSnapshots(matching query: String? = nil) -> [SavedWorkspaceSnapshotSummary] {
		let context = container.viewContext
		let request = WorkspaceSnapshotEntity.fetchRequest()
		request.sortDescriptors = [
			NSSortDescriptor(key: #keyPath(WorkspaceSnapshotEntity.isPinned), ascending: false),
			NSSortDescriptor(key: #keyPath(WorkspaceSnapshotEntity.updatedAt), ascending: false)
		]

		if let query {
			let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
			if !trimmedQuery.isEmpty {
				request.predicate = NSPredicate(format: "searchText CONTAINS[cd] %@", trimmedQuery)
			}
		}

		do {
			return try context.fetch(request).map { entity in
				Self.makeSnapshotSummary(from: entity, paneCount: Self.snapshotPaneCount(from: entity.rootNode))
			}
		} catch {
			logger.error("Core Data failed to list saved workspace snapshots. The app will continue, but the saved-workspace index could not be read. Error: \(String(describing: error), privacy: .public)")
			return []
		}
	}

	func loadWorkspaceSnapshot(id: WorkspaceSnapshotID) -> SavedWorkspaceSnapshot? {
		let context = container.viewContext
		let request = WorkspaceSnapshotEntity.fetchRequest()
		request.fetchLimit = 1
		request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)

		do {
			guard let entity = try context.fetch(request).first else {
				return nil
			}

			let workspace = Workspace(
				title: entity.title,
				root: Self.decodeSnapshotNode(entity.rootNode, logger: logger),
				focusedPaneID: entity.focusedPaneID.map(PaneID.init(rawValue:))
			)

			guard let normalizedWorkspace = Self.normalizedWorkspace(workspace, logger: logger) else {
				logger.error("A saved workspace snapshot could not be normalized into a restorable workspace. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
				return nil
			}

			let paneSnapshots = entity.sessionSnapshots as? Set<PaneSessionSnapshotEntity> ?? []
			let paneSnapshotsBySessionID: [TerminalSessionID: SavedPaneSessionSnapshot] = Dictionary(
				uniqueKeysWithValues: paneSnapshots.compactMap { sessionSnapshot in
				guard let paneSnapshot = Self.decodePaneSessionSnapshot(sessionSnapshot, logger: logger) else {
					return nil
				}
				return (paneSnapshot.id, paneSnapshot)
			})

			return SavedWorkspaceSnapshot(
				id: WorkspaceSnapshotID(rawValue: entity.id),
				title: entity.title,
				createdAt: entity.createdAt,
				updatedAt: entity.updatedAt,
				lastOpenedAt: entity.lastOpenedAt,
				isPinned: entity.isPinned,
				notes: entity.notes,
				previewText: entity.previewText,
				workspace: normalizedWorkspace,
				paneSnapshotsBySessionID: paneSnapshotsBySessionID
			)
		} catch {
			logger.error("Core Data failed to load a saved workspace snapshot. The live session remains available, but the snapshot could not be read. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
			return nil
		}
	}

	func deleteWorkspaceSnapshot(id: WorkspaceSnapshotID) {
		let context = container.viewContext
		context.performAndWait {
			do {
				let request = WorkspaceSnapshotEntity.fetchRequest()
				request.fetchLimit = 1
				request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
				guard let entity = try context.fetch(request).first else {
					return
				}
				context.delete(entity)
				if context.hasChanges {
					try context.save()
				}
			} catch {
				logger.error("Core Data failed to delete a saved workspace snapshot. The snapshot remains in the library. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
	}

	func markWorkspaceSnapshotOpened(_ id: WorkspaceSnapshotID) {
		let context = container.viewContext
		context.performAndWait {
			do {
				let request = WorkspaceSnapshotEntity.fetchRequest()
				request.fetchLimit = 1
				request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
				guard let entity = try context.fetch(request).first else {
					return
				}
				let now = Date()
				entity.lastOpenedAt = now
				entity.updatedAt = now
				if context.hasChanges {
					try context.save()
				}
			} catch {
				logger.error("Core Data failed to update the last-opened date for a saved workspace snapshot. The snapshot remains usable, but its recency metadata is stale. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
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

	private nonisolated static func syncSnapshotNode(
		_ node: PaneNode?,
		context: NSManagedObjectContext,
		sessionSnapshotsByID: [UUID: PaneSessionSnapshotEntity]
	) throws -> PaneSnapshotNodeEntity? {
		guard let node else {
			return nil
		}

		switch node {
			case .leaf(let leaf):
				guard let sessionSnapshot = sessionSnapshotsByID[leaf.sessionID.rawValue] else {
					throw SnapshotPersistenceError.missingSessionSnapshot(sessionID: leaf.sessionID.rawValue)
				}

				let nodeEntity = PaneSnapshotNodeEntity(context: context)
				nodeEntity.id = leaf.id.rawValue
				nodeEntity.kind = PaneNodeKind.leaf.rawValue
				nodeEntity.sessionSnapshotID = sessionSnapshot.id
				nodeEntity.axis = nil
				nodeEntity.fraction = 0
				nodeEntity.firstChild = nil
				nodeEntity.secondChild = nil
				return nodeEntity

			case .split(let split):
				let nodeEntity = PaneSnapshotNodeEntity(context: context)
				nodeEntity.id = split.id.rawValue
				nodeEntity.kind = PaneNodeKind.split.rawValue
				nodeEntity.sessionSnapshotID = nil
				nodeEntity.axis = split.axis.rawValue
				nodeEntity.fraction = split.fraction
				nodeEntity.firstChild = try syncSnapshotNode(
					split.first,
					context: context,
					sessionSnapshotsByID: sessionSnapshotsByID
				)
				nodeEntity.secondChild = try syncSnapshotNode(
					split.second,
					context: context,
					sessionSnapshotsByID: sessionSnapshotsByID
				)
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

	private static func decodeSnapshotNode(_ nodeEntity: PaneSnapshotNodeEntity?, logger: Logger) -> PaneNode? {
		guard let nodeEntity else {
			return nil
		}

		switch PaneNodeKind(rawValue: nodeEntity.kind) {
			case .leaf:
				guard let sessionSnapshotID = nodeEntity.sessionSnapshotID else {
					logger.error("A saved workspace snapshot leaf node is missing its session snapshot identifier. That pane will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				return .leaf(
					PaneLeaf(
						id: PaneID(rawValue: nodeEntity.id),
						sessionID: TerminalSessionID(rawValue: sessionSnapshotID)
					)
				)

			case .split:
				guard let axis = nodeEntity.axis.flatMap(PaneSplit.Axis.init(rawValue:)) else {
					logger.error("A saved workspace snapshot split node is missing or has an invalid axis. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				guard let first = decodeSnapshotNode(nodeEntity.firstChild, logger: logger),
					  let second = decodeSnapshotNode(nodeEntity.secondChild, logger: logger)
				else {
					logger.error("A saved workspace snapshot split node is missing one or both child nodes. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
				logger.error("A saved workspace snapshot pane node has an unknown kind value. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
				return nil
		}
	}

	private static func normalizedWorkspace(_ workspace: Workspace, logger: Logger) -> Workspace? {
		guard let root = workspace.root else {
			logger.error("A persisted workspace has no root pane tree. That empty workspace will be discarded during restore. Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
			return nil
		}

		let leaves = root.leaves()
		guard !leaves.isEmpty else {
			logger.error("A persisted workspace decoded to an empty pane tree. That workspace will be discarded during restore. Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
			return nil
		}

		let focusedPaneID = if let focusedPaneID = workspace.focusedPaneID,
			leaves.contains(where: { $0.id == focusedPaneID }) {
			focusedPaneID
		} else {
			leaves[0].id
		}

		return Workspace(
			id: workspace.id,
			title: workspace.title,
			root: root,
			focusedPaneID: focusedPaneID
		)
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

	private static func lineCount(for transcript: String?) -> Int {
		guard let transcript, !transcript.isEmpty else {
			return 0
		}
		return transcript.reduce(into: 1) { count, character in
			if character == "\n" {
				count += 1
			}
		}
	}

	private static func previewText(for transcript: String?) -> String? {
		guard let transcript else {
			return nil
		}

		let trimmedLines = transcript
			.split(whereSeparator: \.isNewline)
			.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }

		guard let firstLine = trimmedLines.first else {
			return nil
		}

		return String(firstLine.prefix(160))
	}

	private func launchConfigurationForSnapshot(from session: TerminalSession) -> TerminalLaunchConfiguration {
		let resolvedCurrentDirectory = session.currentDirectory ?? session.launchConfiguration.currentDirectory
		return TerminalLaunchConfiguration(
			executable: session.launchConfiguration.executable,
			arguments: session.launchConfiguration.arguments,
			environment: session.launchConfiguration.environment,
			currentDirectory: resolvedCurrentDirectory
		)
	}

	private func normalizedSearchText(from components: [String]) -> String {
		components
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: "\n")
	}

	private static func snapshotPaneCount(from rootNode: PaneSnapshotNodeEntity?) -> Int {
		guard let rootNode else {
			return 0
		}

		switch PaneNodeKind(rawValue: rootNode.kind) {
			case .leaf:
				return 1
			case .split:
				return snapshotPaneCount(from: rootNode.firstChild) + snapshotPaneCount(from: rootNode.secondChild)
			case .none:
				return 0
		}
	}

	private static func makeSnapshotSummary(
		from entity: WorkspaceSnapshotEntity,
		paneCount: Int
	) -> SavedWorkspaceSnapshotSummary {
		SavedWorkspaceSnapshotSummary(
			id: WorkspaceSnapshotID(rawValue: entity.id),
			title: entity.title,
			createdAt: entity.createdAt,
			updatedAt: entity.updatedAt,
			lastOpenedAt: entity.lastOpenedAt,
			isPinned: entity.isPinned,
			previewText: entity.previewText,
			paneCount: paneCount
		)
	}

	private static func decodePaneSessionSnapshot(
		_ entity: PaneSessionSnapshotEntity,
		logger: Logger
	) -> SavedPaneSessionSnapshot? {
		do {
			let arguments = try decode([String].self, from: entity.argumentsData)
			let environment = try decode([String]?.self, from: entity.environmentData)
			return SavedPaneSessionSnapshot(
				id: TerminalSessionID(rawValue: entity.id),
				title: entity.title,
				launchConfiguration: TerminalLaunchConfiguration(
					executable: entity.executable,
					arguments: arguments,
					environment: environment,
					currentDirectory: entity.currentDirectory
				),
				transcript: entity.transcript,
				transcriptByteCount: Int(entity.transcriptByteCount),
				transcriptLineCount: Int(entity.transcriptLineCount),
				previewText: entity.previewText
			)
		} catch {
			logger.error("A saved workspace pane session snapshot could not be decoded. That pane history will be skipped during restore. Session snapshot ID: \(entity.id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
			return nil
		}
	}

	private static func encode<T: Encodable>(_ value: T) throws -> Data {
		try JSONEncoder().encode(value)
	}

	private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) throws -> T {
		guard let data else {
			throw SnapshotPersistenceError.missingEncodedPayload(typeName: String(describing: type))
		}
		return try JSONDecoder().decode(type, from: data)
	}

	private struct PendingPaneSessionSnapshot {
		let sessionID: TerminalSessionID
		let title: String
		let launchConfiguration: TerminalLaunchConfiguration
		let argumentsData: Data?
		let environmentData: Data?
		let transcript: String?
		let transcriptByteCount: Int
		let transcriptLineCount: Int
		let previewText: String?
	}
}

private enum PaneNodeKind: String {
	case leaf
	case split
}

private enum SnapshotPersistenceError: Error {
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
