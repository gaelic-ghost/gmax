/*
 WorkspacePersistenceController owns the durable workspace repository surface.
 It restores per-window live and recent workspace state, manages saved library
 entries plus their current revisions, and gives the rest of the app one
 main-actor entrypoint into Core Data-backed workspace persistence.
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

	func loadWorkspaces(for sceneIdentity: WorkspaceSceneIdentity) -> [Workspace] {
		let context = container.viewContext
		return loadPlacements(role: .live, sceneIdentity: sceneIdentity, in: context)
			.compactMap { placement in
				guard let revision = workspaceRevision(for: placement.workspace, placement: placement) else {
					return nil
				}
				return revision.workspace
			}
	}

	func loadRecentlyClosedWorkspaces(for sceneIdentity: WorkspaceSceneIdentity) -> [PersistedRecentlyClosedWorkspace] {
		let context = container.viewContext
		return loadPlacements(role: .recent, sceneIdentity: sceneIdentity, in: context)
			.compactMap { placement in
				guard let revision = workspaceRevision(for: placement.workspace, placement: placement) else {
					return nil
				}
				return PersistedRecentlyClosedWorkspace(
					revision: revision,
					formerIndex: Int(placement.restoreSortOrder)
				)
			}
	}

	func saveSceneState(
		for sceneIdentity: WorkspaceSceneIdentity,
		liveWorkspaces: [Workspace],
		recentlyClosedWorkspaces: [RecentlyClosedWorkspaceStateInput],
		sessions: TerminalSessionRegistry,
		liveTranscriptsByWorkspaceID: [WorkspaceID: [TerminalSessionID: String]] = [:]
	) {
		let context = container.viewContext
		context.performAndWait {
			do {
				let livePlacements = loadPlacements(role: .live, sceneIdentity: sceneIdentity, in: context)
				let recentPlacements = loadPlacements(role: .recent, sceneIdentity: sceneIdentity, in: context)
				var existingPlacementsByID = Dictionary(uniqueKeysWithValues: (livePlacements + recentPlacements).map { ($0.id, $0) })
				let existingWorkspaceRequest = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
				let existingWorkspaces = try context.fetch(existingWorkspaceRequest)
				var existingWorkspacesByID = Dictionary(uniqueKeysWithValues: existingWorkspaces.map { ($0.id, $0) })
				var retainedPlacementIDs: Set<UUID> = []
				var retainedWorkspaceIDs: Set<UUID> = []

				for (sortOrder, workspace) in liveWorkspaces.enumerated() {
					let workspaceEntity = try upsertWorkspaceEntity(
						for: workspace,
						context: context,
						existingWorkspacesByID: &existingWorkspacesByID,
						sessions: sessions,
						transcriptsBySessionID: liveTranscriptsByWorkspaceID[workspace.id] ?? [:]
					)
					let placement = existingPlacementsByID.removeValue(forKey: workspace.id.rawValue)
						?? WorkspacePlacementEntity(context: context)
					let now = Date()
					if placement.objectID.isTemporaryID {
						placement.id = workspace.id.rawValue
						placement.createdAt = now
					}
					placement.role = WorkspacePlacementRole.live.rawValue
					placement.windowID = sceneIdentity.windowID
					placement.sortOrder = Int64(sortOrder)
					placement.restoreSortOrder = Int64(sortOrder)
					placement.updatedAt = now
					placement.lastOpenedAt = nil
					placement.isPinned = false
					placement.workspace = workspaceEntity
					refreshListingMetadata(on: placement, from: workspaceEntity)
					retainedPlacementIDs.insert(placement.id)
					retainedWorkspaceIDs.insert(workspaceEntity.id)
				}

				for (stackIndex, recentlyClosedWorkspace) in recentlyClosedWorkspaces.enumerated() {
					let workspaceEntity = try upsertWorkspaceEntity(
						for: recentlyClosedWorkspace.workspace,
						context: context,
						existingWorkspacesByID: &existingWorkspacesByID,
						sessionSnapshots: makeSessionSnapshots(
							for: recentlyClosedWorkspace.workspace,
							launchConfigurationsBySessionID: recentlyClosedWorkspace.launchConfigurationsBySessionID,
							titlesBySessionID: recentlyClosedWorkspace.titlesBySessionID,
							transcriptsBySessionID: recentlyClosedWorkspace.transcriptsBySessionID
						)
					)
					let placement = existingPlacementsByID.removeValue(forKey: workspaceEntity.id)
						?? WorkspacePlacementEntity(context: context)
					let now = Date()
					if placement.objectID.isTemporaryID {
						placement.id = workspaceEntity.id
						placement.createdAt = now
					}
					placement.role = WorkspacePlacementRole.recent.rawValue
					placement.windowID = sceneIdentity.windowID
					placement.sortOrder = Int64(stackIndex)
					placement.restoreSortOrder = Int64(recentlyClosedWorkspace.formerIndex)
					placement.updatedAt = now
					placement.lastOpenedAt = nil
					placement.isPinned = false
					placement.workspace = workspaceEntity
					refreshListingMetadata(on: placement, from: workspaceEntity)
					retainedPlacementIDs.insert(placement.id)
					retainedWorkspaceIDs.insert(workspaceEntity.id)
				}

				for stalePlacement in existingPlacementsByID.values where !retainedPlacementIDs.contains(stalePlacement.id) {
					context.delete(stalePlacement)
				}

				try deleteOrphanedWorkspaceRecords(
					existingWorkspacesByID: existingWorkspacesByID,
					retainedWorkspaceIDs: retainedWorkspaceIDs,
					context: context
				)

				if context.hasChanges {
					try context.save()
				}
			} catch {
				Logger.persistence.error("Core Data could not save the window-scoped workspace state for the active scene. The current session remains live, but this window's latest workspace changes were not persisted to disk. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
	}

	func saveWorkspaceToLibrary(
		from workspace: Workspace,
		sessions: TerminalSessionRegistry,
		transcriptsBySessionID: [TerminalSessionID: String] = [:],
		notes: String? = nil,
		isPinned: Bool? = nil
	) -> SavedWorkspaceListing? {
		let context = container.viewContext
		var createdListing: SavedWorkspaceListing?
		context.performAndWait {
			do {
				let savedWorkspaceID = workspace.savedWorkspaceID ?? SavedWorkspaceID()
				let now = Date()
				let workspaceEntity = WorkspaceEntity(context: context)
				workspaceEntity.id = UUID()
				workspaceEntity.savedWorkspaceID = savedWorkspaceID.rawValue
				try updateWorkspaceEntity(
					workspaceEntity,
					from: workspace,
					context: context,
					sessionSnapshots: makeSessionSnapshots(
						for: workspace,
						sessions: sessions,
						transcriptsBySessionID: transcriptsBySessionID
					),
					notes: notes,
					now: now
				)

				let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
				request.fetchLimit = 1
				request.predicate = NSPredicate(format: "id == %@", savedWorkspaceID.rawValue as CVarArg)
				let placement = try context.fetch(request).first ?? WorkspacePlacementEntity(context: context)
				if placement.objectID.isTemporaryID {
					placement.id = savedWorkspaceID.rawValue
					placement.createdAt = now
				}
				placement.role = WorkspacePlacementRole.library.rawValue
				placement.windowID = nil
				placement.sortOrder = 0
				placement.restoreSortOrder = 0
				placement.updatedAt = now
				placement.lastOpenedAt = placement.lastOpenedAt
				placement.isPinned = isPinned ?? placement.isPinned
				placement.workspace = workspaceEntity
				refreshListingMetadata(on: placement, from: workspaceEntity)

				if context.hasChanges {
					try context.save()
				}

				createdListing = makeSavedWorkspaceListing(from: placement)
			} catch {
				Logger.persistence.error("Core Data failed to save a workspace revision into the library. The live workspace remains available, but the saved copy was not written. Workspace title: \(workspace.title, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}

		return createdListing
	}

	func listSavedWorkspaces(matching query: String? = nil) -> [SavedWorkspaceListing] {
		let context = container.viewContext
		let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
		request.sortDescriptors = [
			NSSortDescriptor(key: #keyPath(WorkspacePlacementEntity.isPinned), ascending: false),
			NSSortDescriptor(key: #keyPath(WorkspacePlacementEntity.updatedAt), ascending: false)
		]
		request.predicate = NSPredicate(format: "role == %@", WorkspacePlacementRole.library.rawValue)

		if let query {
			let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
			if !trimmedQuery.isEmpty {
				request.predicate = NSCompoundPredicate(
					andPredicateWithSubpredicates: [
						NSPredicate(format: "role == %@", WorkspacePlacementRole.library.rawValue),
						NSPredicate(format: "searchText CONTAINS[cd] %@", trimmedQuery),
					]
				)
			}
		}

		do {
			return try context.fetch(request).map(makeSavedWorkspaceListing(from:))
		} catch {
			Logger.persistence.error("Core Data failed to list saved workspaces from the library. The app will continue, but the library index could not be read. Error: \(String(describing: error), privacy: .public)")
			return []
		}
	}

	func loadSavedWorkspace(id: SavedWorkspaceID) -> WorkspaceRevision? {
		let context = container.viewContext
		let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
		request.fetchLimit = 1
		request.predicate = NSPredicate(
			format: "id == %@ AND role == %@",
			id.rawValue as CVarArg,
			WorkspacePlacementRole.library.rawValue
		)

		do {
			guard let placement = try context.fetch(request).first else {
				Logger.persistence.error("The saved-workspace library could not find the requested entry during reopen. The entry may have been deleted or the library selection may be stale. Saved workspace ID: \(id.rawValue.uuidString, privacy: .public)")
				return nil
			}
			return workspaceRevision(for: placement.workspace, placement: placement)
		} catch {
			Logger.persistence.error("Core Data failed while reading a saved workspace from the library. The live session remains available, but the requested saved revision could not be loaded. Saved workspace ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
			return nil
		}
	}

	@discardableResult
	func deleteSavedWorkspace(id: SavedWorkspaceID) -> Bool {
		let context = container.viewContext
		var didDeleteSavedWorkspace = false
		context.performAndWait {
			do {
				let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
				request.fetchLimit = 1
				request.predicate = NSPredicate(
					format: "id == %@ AND role == %@",
					id.rawValue as CVarArg,
					WorkspacePlacementRole.library.rawValue
				)
				guard let placement = try context.fetch(request).first else {
					Logger.persistence.error("The saved-workspace library could not find the entry requested for deletion. The library may already be up to date, or the selection may have gone stale. Saved workspace ID: \(id.rawValue.uuidString, privacy: .public)")
					return
				}

				let libraryWorkspaceID = placement.workspace?.id
				context.delete(placement)

				if let libraryWorkspaceID {
					try deleteOrphanedWorkspaceRecords(
						existingWorkspacesByID: [libraryWorkspaceID: try requireWorkspaceEntity(id: libraryWorkspaceID, context: context)],
						retainedWorkspaceIDs: [],
						context: context
					)
				}

				if context.hasChanges {
					try context.save()
				}
				didDeleteSavedWorkspace = true
			} catch {
				Logger.persistence.error("Core Data failed to delete a saved workspace from the library. The entry remains available. Saved workspace ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
		return didDeleteSavedWorkspace
	}

	func markSavedWorkspaceOpened(_ id: SavedWorkspaceID) {
		let context = container.viewContext
		context.performAndWait {
			do {
				let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
				request.fetchLimit = 1
				request.predicate = NSPredicate(
					format: "id == %@ AND role == %@",
					id.rawValue as CVarArg,
					WorkspacePlacementRole.library.rawValue
				)
				guard let placement = try context.fetch(request).first else {
					return
				}
				let now = Date()
				placement.lastOpenedAt = now
				placement.updatedAt = now
				if context.hasChanges {
					try context.save()
				}
			} catch {
				Logger.persistence.error("Core Data failed to update the recency metadata for a saved workspace. The entry remains usable, but its last-opened date is stale. Saved workspace ID: \(id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
				context.rollback()
			}
		}
	}
}

extension WorkspacePersistenceController {
	func loadPlacements(
		role: WorkspacePlacementRole,
		sceneIdentity: WorkspaceSceneIdentity,
		in context: NSManagedObjectContext? = nil
	) -> [WorkspacePlacementEntity] {
		let context = context ?? container.viewContext
		let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
		request.sortDescriptors = [NSSortDescriptor(key: #keyPath(WorkspacePlacementEntity.sortOrder), ascending: true)]
		switch role {
			case .library:
				request.predicate = NSPredicate(format: "role == %@", role.rawValue)
			case .live, .recent:
				request.predicate = NSCompoundPredicate(
					andPredicateWithSubpredicates: [
						NSPredicate(format: "role == %@", role.rawValue),
						NSPredicate(format: "windowID == %@", sceneIdentity.windowID as CVarArg),
					]
				)
		}

		do {
			return try context.fetch(request)
		} catch {
			Logger.persistence.error("Core Data failed to fetch workspace placements for scene restoration. Role: \(role.rawValue, privacy: .public). Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
			return []
		}
	}

	func upsertWorkspaceEntity(
		for workspace: Workspace,
		context: NSManagedObjectContext,
		existingWorkspacesByID: inout [UUID: WorkspaceEntity],
		sessions: TerminalSessionRegistry,
		transcriptsBySessionID: [TerminalSessionID: String]
	) throws -> WorkspaceEntity {
		let sessionSnapshots = makeSessionSnapshots(
			for: workspace,
			sessions: sessions,
			transcriptsBySessionID: transcriptsBySessionID
		)
		return try upsertWorkspaceEntity(
			for: workspace,
			context: context,
			existingWorkspacesByID: &existingWorkspacesByID,
			sessionSnapshots: sessionSnapshots
		)
	}

	func upsertWorkspaceEntity(
		for workspace: Workspace,
		context: NSManagedObjectContext,
		existingWorkspacesByID: inout [UUID: WorkspaceEntity],
		sessionSnapshots: [WorkspaceSessionSnapshot]
	) throws -> WorkspaceEntity {
		let workspaceEntity = existingWorkspacesByID.removeValue(forKey: workspace.id.rawValue)
			?? WorkspaceEntity(context: context)
		workspaceEntity.id = workspace.id.rawValue
		workspaceEntity.savedWorkspaceID = workspace.savedWorkspaceID?.rawValue
		try updateWorkspaceEntity(
			workspaceEntity,
			from: workspace,
			context: context,
			sessionSnapshots: sessionSnapshots,
			notes: workspaceEntity.notes,
			now: Date()
		)
		return workspaceEntity
	}

	func updateWorkspaceEntity(
		_ workspaceEntity: WorkspaceEntity,
		from workspace: Workspace,
		context: NSManagedObjectContext,
		sessionSnapshots: [WorkspaceSessionSnapshot],
		notes: String?,
		now: Date
	) throws {
		let isNewRecord = workspaceEntity.objectID.isTemporaryID
		if isNewRecord {
			workspaceEntity.createdAt = now
		}
		workspaceEntity.updatedAt = now
		workspaceEntity.title = workspace.title
		workspaceEntity.notes = notes
		workspaceEntity.sortOrder = 0
		if let existingRootNode = workspaceEntity.rootNode {
			context.delete(existingRootNode)
		}
		for existingSessionSnapshot in (workspaceEntity.sessionSnapshots as? Set<PaneSessionSnapshotEntity>) ?? [] {
			context.delete(existingSessionSnapshot)
		}
		workspaceEntity.rootNode = Self.makeNodeEntity(from: workspace.root, context: context)
		let sessionSnapshotEntities = sessionSnapshots.map { sessionSnapshot -> PaneSessionSnapshotEntity in
			let entity = PaneSessionSnapshotEntity(context: context)
			entity.id = sessionSnapshot.id.rawValue
			entity.executable = sessionSnapshot.launchConfiguration.executable
			entity.argumentsData = try? JSONEncoder().encode(sessionSnapshot.launchConfiguration.arguments)
			entity.environmentData = try? JSONEncoder().encode(sessionSnapshot.launchConfiguration.environment)
			entity.currentDirectory = sessionSnapshot.launchConfiguration.currentDirectory
			entity.title = sessionSnapshot.title
			entity.transcript = sessionSnapshot.transcript
			entity.transcriptByteCount = Int64(sessionSnapshot.transcriptByteCount)
			entity.transcriptLineCount = Int64(sessionSnapshot.transcriptLineCount)
			entity.previewText = sessionSnapshot.previewText
			entity.workspace = workspaceEntity
			return entity
		}
		workspaceEntity.sessionSnapshots = NSSet(array: sessionSnapshotEntities)
		workspaceEntity.previewText = sessionSnapshots.lazy.compactMap(\.previewText).first
		workspaceEntity.searchText = makeSearchText(
			title: workspace.title,
			notes: notes,
			previewText: workspaceEntity.previewText,
			sessionSnapshots: sessionSnapshots
		)
	}

	func makeSessionSnapshots(
		for workspace: Workspace,
		sessions: TerminalSessionRegistry,
		transcriptsBySessionID: [TerminalSessionID: String]
	) -> [WorkspaceSessionSnapshot] {
		makeSessionSnapshots(
			for: workspace,
			launchConfigurationsBySessionID: Dictionary(
				uniqueKeysWithValues: (workspace.root?.leaves() ?? []).map { leaf in
					let session = sessions.ensureSession(id: leaf.sessionID)
					let launchConfiguration = TerminalLaunchConfiguration(
						executable: session.launchConfiguration.executable,
						arguments: session.launchConfiguration.arguments,
						environment: session.launchConfiguration.environment,
						currentDirectory: session.currentDirectory ?? session.launchConfiguration.currentDirectory
					)
					return (leaf.sessionID, launchConfiguration)
				}
			),
			titlesBySessionID: Dictionary(
				uniqueKeysWithValues: (workspace.root?.leaves() ?? []).map { leaf in
					let session = sessions.ensureSession(id: leaf.sessionID)
					return (leaf.sessionID, session.title)
				}
			),
			transcriptsBySessionID: transcriptsBySessionID
		)
	}

	func makeSessionSnapshots(
		for workspace: Workspace,
		launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration],
		titlesBySessionID: [TerminalSessionID: String],
		transcriptsBySessionID: [TerminalSessionID: String]
	) -> [WorkspaceSessionSnapshot] {
		(workspace.root?.leaves() ?? []).compactMap { leaf in
			guard let launchConfiguration = launchConfigurationsBySessionID[leaf.sessionID] else {
				return nil
			}
			let transcript = transcriptsBySessionID[leaf.sessionID]
			let transcriptLineCount = transcript.map { transcript in
				transcript.isEmpty ? 0 : transcript.reduce(into: 1) { count, character in
					if character == "\n" {
						count += 1
					}
				}
			} ?? 0
			let previewText = transcript.flatMap(Self.makePreviewText(from:))
			return WorkspaceSessionSnapshot(
				id: leaf.sessionID,
				title: titlesBySessionID[leaf.sessionID] ?? "Shell",
				launchConfiguration: launchConfiguration,
				transcript: transcript,
				transcriptByteCount: transcript?.utf8.count ?? 0,
				transcriptLineCount: transcriptLineCount,
				previewText: previewText
			)
		}
	}

	func workspaceRevision(
		for workspaceEntity: WorkspaceEntity?,
		placement: WorkspacePlacementEntity
	) -> WorkspaceRevision? {
		guard let workspaceEntity else {
			Logger.persistence.error("A workspace placement is missing its referenced workspace payload. That placement will be skipped during restore. Placement ID: \(placement.id.uuidString, privacy: .public)")
			return nil
		}
		let workspace = Workspace(
			id: WorkspaceID(rawValue: workspaceEntity.id),
			title: workspaceEntity.title,
			root: Self.decodeNode(workspaceEntity.rootNode),
			savedWorkspaceID: workspaceEntity.savedWorkspaceID.map(SavedWorkspaceID.init(rawValue:))
		)
		guard let root = workspace.root else {
			Logger.persistence.error("A persisted workspace payload decoded without a root pane tree. That payload will be skipped during restore. Workspace payload ID: \(workspaceEntity.id.uuidString, privacy: .public)")
			return nil
		}
		guard !root.leaves().isEmpty else {
			Logger.persistence.error("A persisted workspace payload decoded into an empty pane tree. That payload will be skipped during restore. Workspace payload ID: \(workspaceEntity.id.uuidString, privacy: .public)")
			return nil
		}

		let sessionSnapshots = decodeSessionSnapshots(from: workspaceEntity)
		return WorkspaceRevision(
			id: workspaceEntity.id,
			savedWorkspaceID: workspaceEntity.savedWorkspaceID.map(SavedWorkspaceID.init(rawValue:)),
			title: workspaceEntity.title,
			createdAt: workspaceEntity.createdAt,
			updatedAt: workspaceEntity.updatedAt,
			lastOpenedAt: placement.lastOpenedAt,
			isPinned: placement.isPinned,
			notes: workspaceEntity.notes,
			previewText: workspaceEntity.previewText,
			workspace: Workspace(
				id: WorkspaceID(rawValue: workspaceEntity.id),
				title: workspace.title,
				root: root,
				savedWorkspaceID: workspace.savedWorkspaceID
			),
			paneSnapshotsBySessionID: sessionSnapshots
		)
	}

	func decodeSessionSnapshots(from workspaceEntity: WorkspaceEntity) -> [TerminalSessionID: WorkspaceSessionSnapshot] {
		let snapshotEntities = workspaceEntity.sessionSnapshots as? Set<PaneSessionSnapshotEntity> ?? []
		return Dictionary(
			uniqueKeysWithValues: snapshotEntities.compactMap { sessionSnapshot in
				guard let argumentsData = sessionSnapshot.argumentsData else {
					Logger.persistence.error("A persisted pane session payload is missing its encoded argument list. That pane payload will be skipped during restore. Session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public)")
					return nil
				}
				do {
					let arguments = try JSONDecoder().decode([String].self, from: argumentsData)
					let environment = try sessionSnapshot.environmentData.map {
						try JSONDecoder().decode([String]?.self, from: $0)
					} ?? nil
					let sessionSnapshotValue = WorkspaceSessionSnapshot(
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
					return (sessionSnapshotValue.id, sessionSnapshotValue)
				} catch {
					Logger.persistence.error("A persisted pane session payload could not be decoded. That pane payload will be skipped during restore. Session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
					return nil
				}
			}
		)
	}

	func refreshListingMetadata(on placement: WorkspacePlacementEntity, from workspaceEntity: WorkspaceEntity) {
		placement.title = workspaceEntity.title
		placement.previewText = workspaceEntity.previewText
		placement.searchText = workspaceEntity.searchText
		placement.paneCount = Int64(Self.decodeNode(workspaceEntity.rootNode)?.leaves().count ?? 0)
	}

	func makeSavedWorkspaceListing(from placement: WorkspacePlacementEntity) -> SavedWorkspaceListing {
		SavedWorkspaceListing(
			id: SavedWorkspaceID(rawValue: placement.id),
			title: placement.title,
			createdAt: placement.createdAt,
			updatedAt: placement.updatedAt,
			lastOpenedAt: placement.lastOpenedAt,
			isPinned: placement.isPinned,
			previewText: placement.previewText,
			paneCount: Int(placement.paneCount)
		)
	}

	func makeSearchText(
		title: String,
		notes: String?,
		previewText: String?,
		sessionSnapshots: [WorkspaceSessionSnapshot]
	) -> String {
		let pieces = [title, notes, previewText]
			.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
		let transcriptPieces = sessionSnapshots.compactMap(\.transcript).filter { !$0.isEmpty }
		return (pieces + transcriptPieces).joined(separator: "\n")
	}

	func deleteOrphanedWorkspaceRecords(
		existingWorkspacesByID: [UUID: WorkspaceEntity],
		retainedWorkspaceIDs: Set<UUID>,
		context: NSManagedObjectContext
	) throws {
		for workspaceEntity in existingWorkspacesByID.values where !retainedWorkspaceIDs.contains(workspaceEntity.id) {
			let livePlacements = (workspaceEntity.placements as? Set<WorkspacePlacementEntity>) ?? []
			let hasLiveReference = livePlacements.contains { placement in
				guard !placement.isDeleted else {
					return false
				}
				guard let role = WorkspacePlacementRole(rawValue: placement.role) else {
					return false
				}
				return role == .live || role == .recent || role == .library
			}
			guard !hasLiveReference else {
				continue
			}
			context.delete(workspaceEntity)
		}
	}

	func requireWorkspaceEntity(id: UUID, context: NSManagedObjectContext) throws -> WorkspaceEntity {
		let request = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
		request.fetchLimit = 1
		request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
		guard let entity = try context.fetch(request).first else {
			throw CocoaError(.validationMissingMandatoryProperty)
		}
		return entity
	}

	static func makePreviewText(from transcript: String) -> String? {
		transcript
			.split(whereSeparator: \.isNewline)
			.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
			.first { !$0.isEmpty }
			.map { String($0.prefix(160)) }
	}
}
