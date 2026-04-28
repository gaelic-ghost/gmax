/*
 WorkspacePersistenceEntities defines the active Core Data managed object
 surface for workspace persistence. These entities model the current payload
 plus placement store used by live and library workspace state, along with
 workspace-owned metadata for window-local recency.
 */

import CoreData
import Foundation

enum PaneNodeKind: String {
    case leaf
    case split
}

enum PersistedPaneContentKind: String {
    case terminal
    case browser
}

@objc(WorkspaceEntity)
final class WorkspaceEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var lastActiveAt: Date
    @NSManaged var recentWindowID: UUID?
    @NSManaged var recentSortOrder: Int64
    @NSManaged var notes: String?
    @NSManaged var previewText: String?
    @NSManaged var searchText: String?
    @NSManaged var sortOrder: Int64
    @NSManaged var rootNode: PaneNodeEntity?
    @NSManaged var placements: NSSet?
    @NSManaged var sessionSnapshots: NSSet?
    @NSManaged var browserSessionSnapshots: NSSet?
}

@objc(PaneNodeEntity)
final class PaneNodeEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var kind: String
    @NSManaged var contentKind: String?
    @NSManaged var sessionID: UUID?
    @NSManaged var terminalBackendKind: String?
    @NSManaged var browserSessionID: UUID?
    @NSManaged var axis: String?
    @NSManaged var fraction: Double
    @NSManaged var workspaceRoot: WorkspaceEntity?
    @NSManaged var firstChild: PaneNodeEntity?
    @NSManaged var firstParent: PaneNodeEntity?
    @NSManaged var secondChild: PaneNodeEntity?
    @NSManaged var secondParent: PaneNodeEntity?
}

@objc(WorkspacePlacementEntity)
final class WorkspacePlacementEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var role: String
    @NSManaged var windowID: UUID?
    @NSManaged var sortOrder: Int64
    @NSManaged var restoreSortOrder: Int64
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var lastOpenedAt: Date?
    @NSManaged var isPinned: Bool
    @NSManaged var title: String
    @NSManaged var previewText: String?
    @NSManaged var searchText: String?
    @NSManaged var paneCount: Int64
    @NSManaged var workspace: WorkspaceEntity?
}

@objc(LibraryItemEntity)
final class LibraryItemEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var kind: String
    @NSManaged var workspaceID: UUID?
    @NSManaged var windowID: UUID?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var lastOpenedAt: Date?
    @NSManaged var isPinned: Bool
    @NSManaged var title: String
    @NSManaged var previewText: String?
    @NSManaged var searchText: String?
    @NSManaged var paneCount: Int64
    @NSManaged var workspaceCount: Int64
}

@objc(WorkspaceWindowEntity)
final class WorkspaceWindowEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var lastActiveAt: Date
    @NSManaged var selectedWorkspaceID: UUID?
    @NSManaged var selectedPaneID: UUID?
    @NSManaged var title: String?
    @NSManaged var isOpen: Bool
}

@objc(WindowWorkspaceMembershipEntity)
final class WindowWorkspaceMembershipEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var windowID: UUID
    @NSManaged var workspaceID: UUID
    @NSManaged var sortOrder: Int64
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

@objc(WorkspaceWindowStateEntity)
final class WorkspaceWindowStateEntity: NSManagedObject {
    @NSManaged var windowID: UUID
    @NSManaged var selectedWorkspaceID: UUID?
    @NSManaged var selectedPaneID: UUID?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
}

@objc(PaneSessionSnapshotEntity)
final class PaneSessionSnapshotEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var executable: String
    @NSManaged var argumentsData: Data?
    @NSManaged var environmentData: Data?
    @NSManaged var currentDirectory: String?
    @NSManaged var title: String
    @NSManaged var transcript: String?
    @NSManaged var normalScrollPosition: Double
    @NSManaged var hasNormalScrollPosition: Bool
    @NSManaged var wasAlternateBufferActive: Bool
    @NSManaged var transcriptByteCount: Int64
    @NSManaged var transcriptLineCount: Int64
    @NSManaged var previewText: String?
    @NSManaged var workspace: WorkspaceEntity?
}

@objc(BrowserPaneSessionSnapshotEntity)
final class BrowserPaneSessionSnapshotEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var title: String
    @NSManaged var url: String?
    @NSManaged var lastCommittedURL: String?
    @NSManaged var state: String
    @NSManaged var failureDescription: String?
    @NSManaged var previewText: String?
    @NSManaged var historyURLsData: Data?
    @NSManaged var historyTitlesData: Data?
    @NSManaged var hasHistory: Bool
    @NSManaged var historyCurrentIndex: Int64
    @NSManaged var workspace: WorkspaceEntity?
}
