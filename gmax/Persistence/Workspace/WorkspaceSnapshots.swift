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

struct SavedWorkspaceListing: Identifiable, Hashable, Codable {
    var id: WorkspaceID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var isPinned: Bool
    var previewText: String?
    var paneCount: Int

    nonisolated init(
        id: WorkspaceID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        lastOpenedAt: Date?,
        isPinned: Bool,
        previewText: String?,
        paneCount: Int,
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastOpenedAt = lastOpenedAt
        self.isPinned = isPinned
        self.previewText = previewText
        self.paneCount = paneCount
    }

    nonisolated init?(libraryItem: LibraryItemListing) {
        guard libraryItem.kind == .workspace, let workspaceID = libraryItem.workspaceID else {
            return nil
        }

        self.init(
            id: workspaceID,
            title: libraryItem.title,
            createdAt: libraryItem.createdAt,
            updatedAt: libraryItem.updatedAt,
            lastOpenedAt: libraryItem.lastOpenedAt,
            isPinned: libraryItem.isPinned,
            previewText: libraryItem.previewText,
            paneCount: libraryItem.paneCount,
        )
    }
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
    var transcriptsBySessionID: [TerminalSessionID: String]
}
