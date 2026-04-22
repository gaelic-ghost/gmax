import Foundation

struct SavedWorkspaceID: RawRepresentable, Hashable, Codable, Identifiable {
    var rawValue = UUID()

    var id: UUID { rawValue }
}

struct WorkspaceSceneIdentity: Codable, Hashable {
    var windowID = UUID()
}

enum WorkspacePlacementRole: String, Codable, Hashable {
    case live
    case recent
    case library
}

struct WorkspaceSessionSnapshot: Hashable, Codable, Identifiable {
    var id: TerminalSessionID
    var title: String
    var launchConfiguration: TerminalLaunchConfiguration
    var transcript: String?
    var transcriptByteCount: Int
    var transcriptLineCount: Int
    var previewText: String?
}

struct WorkspaceListing: Hashable, Codable {
    var title: String
    var previewText: String?
    var paneCount: Int
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isPinned: Bool
}

struct SavedWorkspaceListing: Identifiable, Hashable, Codable {
    var id: SavedWorkspaceID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isPinned: Bool
    var previewText: String?
    var paneCount: Int
}

struct WorkspaceRevision: Identifiable, Hashable, Codable {
    var id: UUID
    var savedWorkspaceID: SavedWorkspaceID?
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isPinned: Bool
    var notes: String?
    var previewText: String?
    var workspace: Workspace
    var paneSnapshotsBySessionID: [TerminalSessionID: WorkspaceSessionSnapshot]
}

struct PersistedRecentlyClosedWorkspace: Hashable, Codable {
    var revision: WorkspaceRevision
    var formerIndex: Int
}

struct RecentlyClosedWorkspaceStateInput {
    var workspace: Workspace
    var formerIndex: Int
    var launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration]
    var titlesBySessionID: [TerminalSessionID: String]
    var transcriptsBySessionID: [TerminalSessionID: String]
}
