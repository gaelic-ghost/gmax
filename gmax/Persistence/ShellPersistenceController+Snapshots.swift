//
//  ShellPersistenceController+Snapshots.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import CoreData
import Foundation
import OSLog

extension ShellPersistenceController {
	nonisolated static func existingSnapshotEntity(
		forSourceWorkspaceID workspaceID: WorkspaceID,
		in context: NSManagedObjectContext
	) throws -> WorkspaceSnapshotEntity? {
		let request = NSFetchRequest<WorkspaceSnapshotEntity>(entityName: "WorkspaceSnapshotEntity")
		request.fetchLimit = 1
		request.predicate = NSPredicate(format: "sourceWorkspaceID == %@", workspaceID.rawValue as CVarArg)
		return try context.fetch(request).first
	}

	nonisolated static func deleteExistingSnapshotContents(
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

	nonisolated static func syncSnapshotNode(
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

	nonisolated static func decodeSnapshotNode(_ nodeEntity: PaneSnapshotNodeEntity?, logger: Logger) -> PaneNode? {
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

	nonisolated static func lineCount(for transcript: String?) -> Int {
		guard let transcript, !transcript.isEmpty else {
			return 0
		}
		return transcript.reduce(into: 1) { count, character in
			if character == "\n" {
				count += 1
			}
		}
	}

	nonisolated static func previewText(for transcript: String?) -> String? {
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

	func launchConfigurationForSnapshot(from session: TerminalSession) -> TerminalLaunchConfiguration {
		let resolvedCurrentDirectory = session.currentDirectory ?? session.launchConfiguration.currentDirectory
		return TerminalLaunchConfiguration(
			executable: session.launchConfiguration.executable,
			arguments: session.launchConfiguration.arguments,
			environment: session.launchConfiguration.environment,
			currentDirectory: resolvedCurrentDirectory
		)
	}

	func normalizedSearchText(from components: [String]) -> String {
		components
			.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
			.filter { !$0.isEmpty }
			.joined(separator: "\n")
	}

	nonisolated static func snapshotPaneCount(from rootNode: PaneSnapshotNodeEntity?) -> Int {
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

	nonisolated static func makeSnapshotSummary(
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

	nonisolated static func decodePaneSessionSnapshot(
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

	nonisolated static func encode<T: Encodable>(_ value: T) throws -> Data {
		try JSONEncoder().encode(value)
	}

	nonisolated static func decode<T: Decodable>(_ type: T.Type, from data: Data?) throws -> T {
		guard let data else {
			throw SnapshotPersistenceError.missingEncodedPayload(typeName: String(describing: type))
		}
		return try JSONDecoder().decode(type, from: data)
	}

	struct PendingPaneSessionSnapshot {
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
