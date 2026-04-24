import Foundation

struct WorkspaceSceneIdentity: Codable, Hashable {
    var windowID = UUID()
}

enum WorkspacePlacementRole: String, Codable, Hashable {
    case live
}

enum LibraryItemKind: String, Codable, Hashable {
    case workspace
    case window
}

enum WorkspacePersistenceLegacy {
    nonisolated static let recentPlacementRoleRawValue = "recent"
    nonisolated static let libraryPlacementRoleRawValue = "library"
}

struct WorkspaceSessionSnapshot: Hashable, Codable, Identifiable {
    var id: TerminalSessionID
    var title: String
    var launchConfiguration: TerminalLaunchConfiguration
    var history: WorkspaceSessionHistorySnapshot
    var transcriptByteCount: Int
    var transcriptLineCount: Int
    var previewText: String?

    nonisolated var transcript: String? { history.transcript }
    nonisolated var normalScrollPosition: Double? { history.normalScrollPosition }
    nonisolated var wasAlternateBufferActive: Bool { history.wasAlternateBufferActive }
}

struct WorkspaceSessionHistorySnapshot: Hashable, Codable {
    var transcript: String?
    var normalScrollPosition: Double?
    var wasAlternateBufferActive: Bool
}

enum BrowserSessionSnapshotState: String, Hashable, Codable {
    case idle
    case loading
    case failed
}

struct BrowserSessionSnapshot: Hashable, Codable, Identifiable {
    var id: BrowserSessionID
    var title: String
    var url: String?
    var lastCommittedURL: String?
    var state: BrowserSessionSnapshotState
    var failureDescription: String?
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

struct LibraryItemListing: Identifiable, Hashable, Codable {
    var id: UUID
    var kind: LibraryItemKind
    var workspaceID: WorkspaceID?
    var windowID: WorkspaceSceneIdentity?
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isPinned: Bool
    var previewText: String?
    var paneCount: Int
    var workspaceCount: Int
}

struct WorkspaceRevision: Identifiable, Hashable, Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastActiveAt: Date
    var lastOpenedAt: Date?
    var isPinned: Bool
    var notes: String?
    var previewText: String?
    var workspace: Workspace
    var paneSnapshotsBySessionID: [TerminalSessionID: WorkspaceSessionSnapshot]
    var browserSnapshotsBySessionID: [BrowserSessionID: BrowserSessionSnapshot]
}

struct WindowWorkspaceHistoryRecord: Hashable, Codable {
    var revision: WorkspaceRevision
    var formerIndex: Int
}

struct WorkspaceWindowStateSnapshot: Hashable, Codable {
    var selectedWorkspaceID: WorkspaceID?
}

struct PersistedWorkspaceWindow: Hashable, Codable, Identifiable {
    var id: WorkspaceSceneIdentity
    var selectedWorkspaceID: WorkspaceID?
    var title: String?
    var isOpen: Bool
    var lastActiveAt: Date
}

struct WindowWorkspaceHistoryInput {
    var workspace: Workspace
    var formerIndex: Int
    var launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration]
    var titlesBySessionID: [TerminalSessionID: String]
    var historyBySessionID: [TerminalSessionID: WorkspaceSessionHistorySnapshot]
    var browserSnapshotsBySessionID: [BrowserSessionID: BrowserSessionSnapshot]
}
