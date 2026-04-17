/*
 WorkspacePersistenceController+LegacyMigration quarantines compatibility code
 for pre-placement workspace stores. The active runtime should not call into
 these helpers except when ingesting older on-disk records during one-time
 migration.
 */

import CoreData
import Foundation
import OSLog

extension WorkspacePersistenceController {
	func migrateLegacyPersistenceIfNeeded(
		for sceneIdentity: WorkspaceSceneIdentity,
		context: NSManagedObjectContext
	) throws {
		let placementCountRequest = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
		let existingPlacementCount = try context.count(for: placementCountRequest)
		guard existingPlacementCount == 0 else {
			return
		}

		var migratedAnything = false
		let now = Date()

		let legacyWorkspaceRequest = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
		legacyWorkspaceRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(WorkspaceEntity.sortOrder), ascending: true)]
		let legacyWorkspaceEntities = try context.fetch(legacyWorkspaceRequest)
		for (sortOrder, workspaceEntity) in legacyWorkspaceEntities.enumerated() where workspaceEntity.savedWorkspaceID == nil {
			let placement = WorkspacePlacementEntity(context: context)
			placement.id = workspaceEntity.id
			placement.role = WorkspacePlacementRole.live.rawValue
			placement.windowID = sceneIdentity.windowID
			placement.sortOrder = Int64(sortOrder)
			placement.restoreSortOrder = Int64(sortOrder)
			placement.createdAt = workspaceEntity.createdAt.timeIntervalSinceReferenceDate == 0 ? now : workspaceEntity.createdAt
			placement.updatedAt = workspaceEntity.updatedAt.timeIntervalSinceReferenceDate == 0 ? now : workspaceEntity.updatedAt
			placement.lastOpenedAt = nil
			placement.isPinned = false
			placement.workspace = workspaceEntity

			if workspaceEntity.createdAt.timeIntervalSinceReferenceDate == 0 {
				workspaceEntity.createdAt = now
			}
			if workspaceEntity.updatedAt.timeIntervalSinceReferenceDate == 0 {
				workspaceEntity.updatedAt = now
			}
			refreshListingMetadata(on: placement, from: workspaceEntity)
			migratedAnything = true
		}

		let legacySnapshotRequest = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
		let legacySnapshotEntities = try context.fetch(legacySnapshotRequest)
		for snapshotEntity in legacySnapshotEntities {
			let workspaceEntity = WorkspaceEntity(context: context)
			workspaceEntity.id = UUID()
			workspaceEntity.savedWorkspaceID = snapshotEntity.id
			workspaceEntity.createdAt = snapshotEntity.createdAt
			workspaceEntity.updatedAt = snapshotEntity.updatedAt
			workspaceEntity.title = snapshotEntity.title
			workspaceEntity.notes = snapshotEntity.notes
			workspaceEntity.previewText = snapshotEntity.previewText
			workspaceEntity.searchText = snapshotEntity.searchText
			workspaceEntity.sortOrder = 0
			workspaceEntity.rootNode = Self.makeNodeEntity(
				from: Self.decodeLegacySnapshotNode(snapshotEntity.rootNode),
				context: context
			)
			let legacySessionSnapshots = decodeLegacySessionSnapshots(from: snapshotEntity)
			let sessionSnapshotEntities = legacySessionSnapshots.map { sessionSnapshot -> PaneSessionSnapshotEntity in
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

			let placement = WorkspacePlacementEntity(context: context)
			placement.id = snapshotEntity.id
			placement.role = WorkspacePlacementRole.library.rawValue
			placement.windowID = nil
			placement.sortOrder = 0
			placement.restoreSortOrder = 0
			placement.createdAt = snapshotEntity.createdAt
			placement.updatedAt = snapshotEntity.updatedAt
			placement.lastOpenedAt = snapshotEntity.lastOpenedAt
			placement.isPinned = snapshotEntity.isPinned
			placement.workspace = workspaceEntity
			refreshListingMetadata(on: placement, from: workspaceEntity)
			migratedAnything = true
		}

		if migratedAnything, context.hasChanges {
			try context.save()
			Logger.persistence.notice("Migrated legacy workspace persistence records into the window-scoped placement model. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Legacy live workspace count: \(legacyWorkspaceEntities.count). Legacy saved workspace count: \(legacySnapshotEntities.count)")
		}
	}

	func decodeLegacySessionSnapshots(from snapshotEntity: WorkspaceSnapshotEntity) -> [WorkspaceSessionSnapshot] {
		let sessionSnapshots = snapshotEntity.sessionSnapshots as? Set<PaneSessionSnapshotEntity> ?? []
		return sessionSnapshots.compactMap { sessionSnapshot in
			guard let argumentsData = sessionSnapshot.argumentsData else {
				return nil
			}
			do {
				let arguments = try JSONDecoder().decode([String].self, from: argumentsData)
				let environment = try sessionSnapshot.environmentData.map {
					try JSONDecoder().decode([String]?.self, from: $0)
				} ?? nil
				return WorkspaceSessionSnapshot(
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
			} catch {
				return nil
			}
		}
	}

	nonisolated static func syncLegacySnapshotNode(
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
				nodeEntity.firstChild = try syncLegacySnapshotNode(
					split.first,
					context: context,
					sessionSnapshotsByID: sessionSnapshotsByID
				)
				nodeEntity.secondChild = try syncLegacySnapshotNode(
					split.second,
					context: context,
					sessionSnapshotsByID: sessionSnapshotsByID
				)
				return nodeEntity
		}
	}

	nonisolated static func decodeLegacySnapshotNode(_ nodeEntity: PaneSnapshotNodeEntity?) -> PaneNode? {
		guard let nodeEntity else {
			return nil
		}

		switch PaneNodeKind(rawValue: nodeEntity.kind) {
			case .leaf:
				guard let sessionSnapshotID = nodeEntity.sessionSnapshotID else {
					Logger.persistence.error("A saved workspace snapshot leaf node is missing its session snapshot identifier. That pane will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
					Logger.persistence.error("A saved workspace snapshot split node is missing or has an invalid axis. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
					return nil
				}
				guard let first = decodeLegacySnapshotNode(nodeEntity.firstChild),
					  let second = decodeLegacySnapshotNode(nodeEntity.secondChild)
				else {
					Logger.persistence.error("A saved workspace snapshot split node is missing one or both child nodes. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
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
				Logger.persistence.error("A saved workspace snapshot pane node has an unknown kind value. That node will be skipped during restore. Node ID: \(nodeEntity.id.uuidString, privacy: .public)")
				return nil
		}
	}
}
