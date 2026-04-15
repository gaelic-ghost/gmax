import Foundation

struct WorkspaceSnapshotID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue = UUID()

	var id: UUID { rawValue }
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
