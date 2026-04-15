/*
 WorkspacePersistenceController owns the durable workspace repository surface.
 It loads and saves the live workspace list, manages saved workspace snapshots,
 and gives the rest of the app one main-actor entrypoint into Core Data-backed
 workspace persistence.
 */

import CoreData
import Foundation
import OSLog

@MainActor
final class WorkspacePersistenceController {
	static let shared = WorkspacePersistenceController(profile: .appDefault())

	let container: NSPersistentContainer
	let profile: WorkspacePersistenceProfile

	private init(profile: WorkspacePersistenceProfile) {
		self.profile = profile
		container = Self.makePersistentContainer(profile: profile)
	}

	private init(container: NSPersistentContainer, profile: WorkspacePersistenceProfile) {
		self.profile = profile
		self.container = container
	}

	static func inMemoryForTesting() -> WorkspacePersistenceController {
		let container = makeContainer(
			model: makeManagedObjectModel(),
			description: {
				let description = NSPersistentStoreDescription()
				description.type = NSInMemoryStoreType
				return description
			}(),
			contextName: WorkspacePersistenceProfile.inMemory.contextName
		)

		precondition(
			loadPersistentStores(for: container),
			"The in-memory workspace persistence store must load successfully for tests."
		)

		return WorkspacePersistenceController(container: container, profile: .inMemory)
	}

	func loadWorkspaces() -> [Workspace] {
		let context = container.viewContext
		let request = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
		request.sortDescriptors = [NSSortDescriptor(key: #keyPath(WorkspaceEntity.sortOrder), ascending: true)]

		do {
			return try context.fetch(request).compactMap { workspaceEntity in
				let workspace = Workspace(
					id: WorkspaceID(rawValue: workspaceEntity.id),
					title: workspaceEntity.title,
					root: Self.decodeNode(workspaceEntity.rootNode)
				)
				guard let root = workspace.root else {
					Logger.persistence.error("A persisted workspace has no root pane tree. That empty workspace will be discarded during restore. Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
					return nil
				}

				let leaves = root.leaves()
				guard !leaves.isEmpty else {
					Logger.persistence.error("A persisted workspace decoded to an empty pane tree. That workspace will be discarded during restore. Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
					return nil
				}

				return Workspace(id: workspace.id, title: workspace.title, root: root)
			}
		} catch {
			Logger.persistence.error("Core Data could not read the saved-workspace list from the workspace store. The app will continue with default workspace state for this launch. Error: \(String(describing: error), privacy: .public)")
			return []
		}
	}

	func save(workspaces: [Workspace]) {
		let context = container.viewContext
		context.performAndWait {
			do {
				let existingWorkspaces = try context.fetch(NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity"))
				let existingNodes = try context.fetch(NSFetchRequest<PaneNodeEntity>(entityName: "PaneNodeEntity"))

				var workspacesByID = Dictionary(uniqueKeysWithValues: existingWorkspaces.map { ($0.id, $0) })
				var nodesByID = Dictionary(uniqueKeysWithValues: existingNodes.map { ($0.id, $0) })
				var retainedWorkspaceIDs: Set<UUID> = []
				var retainedNodeIDs: Set<UUID> = []

				for (sortOrder, workspace) in workspaces.enumerated() {
					let workspaceEntity = workspacesByID.removeValue(forKey: workspace.id.rawValue)
						?? WorkspaceEntity(context: context)
					workspaceEntity.id = workspace.id.rawValue
					workspaceEntity.title = workspace.title
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
				Logger.persistence.error("Core Data could not save the latest workspace state. The current session remains live, but the last workspace change was not persisted to disk. Error: \(String(describing: error), privacy: .public)")
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
		let paneSnapshots = (workspace.root?.leaves() ?? []).map { leaf in
			let session = sessions.ensureSession(id: leaf.sessionID)
			let launchConfiguration = TerminalLaunchConfiguration(
				executable: session.launchConfiguration.executable,
				arguments: session.launchConfiguration.arguments,
				environment: session.launchConfiguration.environment,
				currentDirectory: session.currentDirectory ?? session.launchConfiguration.currentDirectory
			)
			let transcript = transcriptsBySessionID[leaf.sessionID]
			let previewText = transcript.flatMap { transcript in
				transcript
					.split(whereSeparator: \.isNewline)
					.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
					.first { !$0.isEmpty }
					.map { String($0.prefix(160)) }
			}
			let transcriptLineCount = transcript.map { transcript in
				transcript.isEmpty ? 0 : transcript.reduce(into: 1) { count, character in
					if character == "\n" {
						count += 1
					}
				}
			} ?? 0
			return (
				sessionID: leaf.sessionID,
				title: session.title,
				launchConfiguration: launchConfiguration,
				argumentsData: try? JSONEncoder().encode(launchConfiguration.arguments),
				environmentData: try? JSONEncoder().encode(launchConfiguration.environment),
				transcript: transcript,
				transcriptByteCount: transcript?.utf8.count ?? 0,
				transcriptLineCount: transcriptLineCount,
				previewText: previewText
			)
		}

		var searchComponents: [String] = [workspace.title]
		if let notes, !notes.isEmpty {
			searchComponents.append(notes)
		}
		for snapshot in paneSnapshots {
			if let previewText = snapshot.previewText, !previewText.isEmpty {
				searchComponents.append(previewText)
			}
			if let transcript = snapshot.transcript, !transcript.isEmpty {
				searchComponents.append(transcript)
			}
		}

		let flattenedSearchText = searchComponents
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: "\n")
		let previewText = paneSnapshots.lazy.compactMap { $0.previewText }.first

		context.performAndWait {
			do {
				let request = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
				request.fetchLimit = 1
				request.predicate = NSPredicate(format: "sourceWorkspaceID == %@", workspace.id.rawValue as CVarArg)
				let snapshotEntity = try context.fetch(request).first ?? WorkspaceSnapshotEntity(context: context)
				let snapshotID = snapshotEntity.sourceWorkspaceID == workspace.id.rawValue
					? WorkspaceSnapshotID(rawValue: snapshotEntity.id)
					: WorkspaceSnapshotID()
				if snapshotEntity.sourceWorkspaceID != workspace.id.rawValue {
					snapshotEntity.id = snapshotID.rawValue
					snapshotEntity.createdAt = now
					snapshotEntity.lastOpenedAt = nil
					snapshotEntity.isPinned = false
				} else {
					if let existingRootNode = snapshotEntity.rootNode {
						context.delete(existingRootNode)
					}
					for sessionSnapshot in (snapshotEntity.sessionSnapshots as? Set<PaneSessionSnapshotEntity>) ?? [] {
						context.delete(sessionSnapshot)
					}
					snapshotEntity.rootNode = nil
					snapshotEntity.sessionSnapshots = nil
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
				var sessionSnapshotsByID: [UUID: PaneSessionSnapshotEntity] = [:]
				for pendingPaneSnapshot in paneSnapshots {
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
					paneCount: workspace.root?.leaves().count ?? 0
				)
			} catch {
				Logger.persistence.error("Core Data failed to create a saved workspace snapshot. The live workspace remains open, but the snapshot was not written. Workspace title: \(workspace.title, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}

		return createdSummary
	}

	func listWorkspaceSnapshots(matching query: String? = nil) -> [SavedWorkspaceSnapshotSummary] {
		let context = container.viewContext
		let request = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
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
				return SavedWorkspaceSnapshotSummary(
					id: WorkspaceSnapshotID(rawValue: entity.id),
					title: entity.title,
					createdAt: entity.createdAt,
					updatedAt: entity.updatedAt,
					lastOpenedAt: entity.lastOpenedAt,
					isPinned: entity.isPinned,
					previewText: entity.previewText,
					paneCount: Self.decodeSnapshotNode(entity.rootNode)?.leaves().count ?? 0
				)
			}
		} catch {
			Logger.persistence.error("Core Data failed to list saved workspace snapshots. The app will continue, but the saved-workspace index could not be read. Error: \(String(describing: error), privacy: .public)")
			return []
		}
	}

	func loadWorkspaceSnapshot(id: WorkspaceSnapshotID) -> SavedWorkspaceSnapshot? {
		let context = container.viewContext
		let request = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
		request.fetchLimit = 1
		request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)

		do {
			guard let entity = try context.fetch(request).first else {
				Logger.persistence.error("The saved-workspace library could not find the requested snapshot during reopen. The snapshot may have been deleted or the library index may be stale. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
				return nil
			}

			let workspace = Workspace(
				title: entity.title,
				root: Self.decodeSnapshotNode(entity.rootNode)
			)

				guard let root = workspace.root else {
					Logger.persistence.error("A saved workspace snapshot decoded into an unusable pane layout during reopen because it had no root pane tree. The snapshot remains on disk, but the app could not rebuild a restorable workspace from it. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
					return nil
				}

				let leaves = root.leaves()
				guard !leaves.isEmpty else {
					Logger.persistence.error("A saved workspace snapshot decoded into an unusable pane layout during reopen because its pane tree was empty. The snapshot remains on disk, but the app could not rebuild a restorable workspace from it. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
					return nil
				}

				let normalizedWorkspace = Workspace(title: workspace.title, root: root)

				let paneSnapshots = entity.sessionSnapshots as? Set<PaneSessionSnapshotEntity> ?? []
			let paneSnapshotsBySessionID: [TerminalSessionID: SavedPaneSessionSnapshot] = Dictionary(
				uniqueKeysWithValues: paneSnapshots.compactMap { sessionSnapshot in
					guard let argumentsData = sessionSnapshot.argumentsData else {
						Logger.persistence.error("A saved workspace pane session snapshot is missing its encoded argument list. That pane history will be skipped during restore. Session snapshot ID: \(sessionSnapshot.id.uuidString, privacy: .public)")
						return nil
					}
					do {
						let arguments = try JSONDecoder().decode([String].self, from: argumentsData)
						let environment = try sessionSnapshot.environmentData.map {
							try JSONDecoder().decode([String]?.self, from: $0)
						} ?? nil
						let paneSnapshot = SavedPaneSessionSnapshot(
							id: TerminalSessionID(rawValue: sessionSnapshot.id),
							title: sessionSnapshot.title,
							launchConfiguration: TerminalLaunchConfiguration(
								executable: sessionSnapshot.executable,
								arguments: arguments,
								environment: environment,
								currentDirectory: sessionSnapshot.currentDirectory
							),
							transcript: sessionSnapshot.transcript,
							transcriptByteCount: Int(sessionSnapshot.transcriptByteCount),
							transcriptLineCount: Int(sessionSnapshot.transcriptLineCount),
							previewText: sessionSnapshot.previewText
						)
						return (paneSnapshot.id, paneSnapshot)
					} catch {
						Logger.persistence.error("A saved workspace pane session snapshot could not be decoded. That pane history will be skipped during restore. Session snapshot ID: \(sessionSnapshot.id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
						return nil
					}
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
			Logger.persistence.error("Core Data failed while reading a saved-workspace snapshot for reopen. The live session remains available, but the requested snapshot could not be loaded from the library store. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
			return nil
		}
	}

	@discardableResult
	func deleteWorkspaceSnapshot(id: WorkspaceSnapshotID) -> Bool {
		let context = container.viewContext
		var didDeleteSnapshot = false
		context.performAndWait {
			do {
				let request = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
				request.fetchLimit = 1
				request.predicate = NSPredicate(format: "id == %@", id.rawValue as CVarArg)
				guard let entity = try context.fetch(request).first else {
					Logger.persistence.error("The saved-workspace library could not find the snapshot requested for deletion. The library may already be up to date, or the selection may have gone stale. Snapshot ID: \(id.rawValue.uuidString, privacy: .public)")
					return
				}
				context.delete(entity)
				if context.hasChanges {
					try context.save()
				}
				didDeleteSnapshot = true
			} catch {
				Logger.persistence.error("Core Data failed to delete a saved workspace snapshot. The snapshot remains in the library. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
		return didDeleteSnapshot
	}

	func markWorkspaceSnapshotOpened(_ id: WorkspaceSnapshotID) {
		let context = container.viewContext
		context.performAndWait {
			do {
				let request = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
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
				Logger.persistence.error("Core Data failed to update the last-opened date for a saved workspace snapshot. The snapshot remains usable, but its recency metadata is stale. Snapshot ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
	}
}
