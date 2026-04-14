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

	let logger: Logger
	let container: NSPersistentContainer

	private init() {
		let logger = Logger.gmax(.persistence)
		self.logger = logger
		self.container = Self.makePersistentContainer(logger: logger)
	}

	private init(container: NSPersistentContainer, logger: Logger) {
		self.logger = logger
		self.container = container
	}

	static func inMemoryForTesting() -> ShellPersistenceController {
		let logger = Logger.gmax(.persistence)
		let container = makeContainer(
			model: makeManagedObjectModel(),
			description: inMemoryStoreDescription(),
			contextName: "ShellPersistence.testInMemoryViewContext"
		)

		precondition(
			loadPersistentStores(for: container, logger: logger),
			"The in-memory shell persistence store must load successfully for tests."
		)

		return ShellPersistenceController(container: container, logger: logger)
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
				logger.error("The saved-workspace library could not find the requested snapshot during reopen. The snapshot may have been deleted or the library index may be stale. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
				return nil
			}

			let workspace = Workspace(
				title: entity.title,
				root: Self.decodeSnapshotNode(entity.rootNode, logger: logger),
				focusedPaneID: entity.focusedPaneID.map(PaneID.init(rawValue:))
			)

			guard let normalizedWorkspace = Self.normalizedWorkspace(workspace, logger: logger) else {
				logger.error("A saved workspace snapshot decoded into an unusable pane layout during reopen. The snapshot remains on disk, but the app could not rebuild a restorable workspace from it. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
				return nil
			}

			let paneSnapshots = entity.sessionSnapshots as? Set<PaneSessionSnapshotEntity> ?? []
			let paneSnapshotsBySessionID: [TerminalSessionID: SavedPaneSessionSnapshot] = Dictionary(
				uniqueKeysWithValues: paneSnapshots.compactMap { sessionSnapshot in
					guard let paneSnapshot = Self.decodePaneSessionSnapshot(sessionSnapshot, logger: logger) else {
						return nil
					}
					return (paneSnapshot.id, paneSnapshot)
				}
			)

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
			logger.error("Core Data failed while reading a saved-workspace snapshot for reopen. The live session remains available, but the requested snapshot could not be loaded from the library store. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
			return nil
		}
	}

	@discardableResult
	func deleteWorkspaceSnapshot(id: WorkspaceSnapshotID) -> Bool {
		let context = container.viewContext
		var didDeleteSnapshot = false
		context.performAndWait {
			do {
				let request = WorkspaceSnapshotEntity.fetchRequest()
				request.fetchLimit = 1
				request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
				guard let entity = try context.fetch(request).first else {
					logger.error("The saved-workspace library could not find the snapshot requested for deletion. The library may already be up to date, or the selection may have gone stale. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
					return
				}
				context.delete(entity)
				if context.hasChanges {
					try context.save()
				}
				didDeleteSnapshot = true
			} catch {
				logger.error("Core Data failed to delete a saved workspace snapshot. The snapshot remains in the library. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
		return didDeleteSnapshot
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
}
