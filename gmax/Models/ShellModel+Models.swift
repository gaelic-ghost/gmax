//
//  ShellModel+Models.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Logging
// MARK: Shared unified-logging categories for the app subsystem.

enum GmaxLogCategory: String {
	case app
	case workspace
	case pane
	case persistence
	case diagnostics
}

extension Logger {
	static func gmax(_ category: GmaxLogCategory) -> Logger {
		Logger(subsystem: "com.gaelic-ghost.gmax", category: category.rawValue)
	}
}

// MARK: - Stable Identifiers
// MARK: Typed wrappers for persisted workspace, pane, split, session, and snapshot IDs.

struct WorkspaceID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	nonisolated init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	nonisolated init() {
		self.rawValue = UUID()
	}
}

struct PaneID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	nonisolated init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	nonisolated init() {
		self.rawValue = UUID()
	}
}

struct SplitID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	nonisolated init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	nonisolated init() {
		self.rawValue = UUID()
	}
}

struct TerminalSessionID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	nonisolated init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	nonisolated init() {
		self.rawValue = UUID()
	}
}

struct WorkspaceSnapshotID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	nonisolated init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	nonisolated init() {
		self.rawValue = UUID()
	}
}

// MARK: - Workspace Commands
// MARK: Shared command enums and persistence defaults used by the shell model.

enum SplitDirection {
	case right
	case down
}

enum PaneFocusDirection {
	case next
	case previous
	case left
	case right
	case up
	case down
}

enum CloseCommandResult {
	case closedPane
	case closedWorkspace
	case closeWindow
	case noAction
}

struct CloseCommandOutcome {
	let result: CloseCommandResult
	let nextSelectedWorkspaceID: WorkspaceID?
}

enum WorkspacePersistenceDefaults {
	static let restoreWorkspacesOnLaunchKey = "workspacePersistence.restoreOnLaunch"
	static let keepRecentlyClosedWorkspacesKey = "workspacePersistence.keepRecentlyClosed"
	static let autoSaveClosedWorkspacesKey = "workspacePersistence.autoSaveClosedWorkspaces"
	static let maxRecentlyClosedWorkspaceCount = 20

	static func registerDefaults(
		in defaults: UserDefaults = .standard,
		globalDefaults: UserDefaults = .standard
	) {
		defaults.register(
			defaults: [
				restoreWorkspacesOnLaunchKey: systemRestoresWindowsByDefault(globalDefaults: globalDefaults),
				keepRecentlyClosedWorkspacesKey: true,
				autoSaveClosedWorkspacesKey: false
			]
		)
	}

	static func systemRestoresWindowsByDefault(globalDefaults: UserDefaults = .standard) -> Bool {
		guard
			let globalDomain = globalDefaults.persistentDomain(forName: UserDefaults.globalDomain),
			let keepsWindows = globalDomain["NSQuitAlwaysKeepsWindows"] as? Bool
		else {
			return true
		}

		return keepsWindows
	}
}

// MARK: - Workspace Snapshots
// MARK: Persisted and in-memory workspace layout types used by the shell model.

struct Workspace: Identifiable, Hashable, Codable {
	var id: WorkspaceID
	var title: String
	var root: PaneNode?
	var focusedPaneID: PaneID?

	nonisolated init(
		id: WorkspaceID = WorkspaceID(),
		title: String,
		root: PaneNode? = nil,
		focusedPaneID: PaneID? = nil
	) {
		self.id = id
		self.title = title
		self.root = root
		self.focusedPaneID = focusedPaneID
	}
}

extension Workspace {
	nonisolated var paneLeaves: [PaneLeaf] {
		root?.leaves() ?? []
	}

	nonisolated var paneCount: Int {
		root?.paneCount() ?? 0
	}
}

indirect enum PaneNode: Hashable, Codable {
	case leaf(PaneLeaf)
	case split(PaneSplit)
}

struct PaneLeaf: Identifiable, Hashable, Codable {
	var id: PaneID
	var sessionID: TerminalSessionID

	nonisolated init(id: PaneID = PaneID(), sessionID: TerminalSessionID = TerminalSessionID()) {
		self.id = id
		self.sessionID = sessionID
	}
}

struct PaneSplit: Hashable, Codable {
	enum Axis: String, Hashable, Codable {
		case horizontal
		case vertical
	}

	var id: SplitID
	var axis: Axis
	var fraction: CGFloat
	var first: PaneNode
	var second: PaneNode

	nonisolated init(
		id: SplitID = SplitID(),
		axis: Axis,
		fraction: CGFloat,
		first: PaneNode,
		second: PaneNode
	) {
		self.id = id
		self.axis = axis
		self.fraction = fraction
		self.first = first
		self.second = second
	}
}

struct SavedPaneSessionSnapshot: Hashable, Codable, Identifiable {
	var id: TerminalSessionID
	var title: String
	var launchConfiguration: TerminalLaunchConfiguration
	var transcript: String?
	var transcriptByteCount: Int
	var transcriptLineCount: Int
	var previewText: String?
}

struct SavedWorkspaceSnapshotSummary: Identifiable, Hashable, Codable {
	var id: WorkspaceSnapshotID
	var title: String
	var createdAt: Date
	var updatedAt: Date
	var lastOpenedAt: Date?
	var isPinned: Bool
	var previewText: String?
	var paneCount: Int
}

struct SavedWorkspaceSnapshot: Identifiable, Hashable, Codable {
	var id: WorkspaceSnapshotID
	var title: String
	var createdAt: Date
	var updatedAt: Date
	var lastOpenedAt: Date?
	var isPinned: Bool
	var notes: String?
	var previewText: String?
	var workspace: Workspace
	var paneSnapshotsBySessionID: [TerminalSessionID: SavedPaneSessionSnapshot]
}

enum PaneRemovalResult {
	case removedLeaf
	case collapsedTo(PaneNode)
}
