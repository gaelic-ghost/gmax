/*
 WorkspacePersistenceController owns the durable workspace repository surface.
 It restores per-window live and recently closed workspace state, manages saved
 library entries plus their current revisions, and gives the rest of the app
 one main-actor entrypoint into Core Data-backed workspace persistence.
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
            contextName: WorkspacePersistenceProfile.inMemory.contextName,
        )

        precondition(
            loadPersistentStores(for: container, profile: .inMemory),
            "The in-memory workspace persistence store must load successfully for tests.",
        )

        return WorkspacePersistenceController(container: container, profile: .inMemory)
    }

    func loadWorkspaceRevisions(for sceneIdentity: WorkspaceSceneIdentity) -> [WorkspaceRevision] {
        let context = container.viewContext
        return context.performAndWait {
            Self.loadPlacements(role: .live, sceneIdentity: sceneIdentity, in: context)
                .compactMap { placement in
                    Self.workspaceRevision(
                        for: placement.workspace,
                        lastOpenedAt: placement.lastOpenedAt,
                        isPinned: placement.isPinned,
                    )
                }
        }
    }

    func loadWorkspaces(for sceneIdentity: WorkspaceSceneIdentity) -> [Workspace] {
        loadWorkspaceRevisions(for: sceneIdentity).map(\.workspace)
    }

    func loadRecentWorkspaceHistory(for sceneIdentity: WorkspaceSceneIdentity) -> [WindowWorkspaceHistoryRecord] {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateLegacyRecentWorkspaceHistory(for: sceneIdentity, in: context)
                return try Self.loadRecentWorkspaceHistoryMemberships(
                    for: sceneIdentity,
                    in: context,
                )
                .compactMap { membership, workspaceEntity in
                    guard let revision = Self.workspaceRevision(for: workspaceEntity) else {
                        return nil
                    }

                    return WindowWorkspaceHistoryRecord(
                        revision: revision,
                        formerIndex: Int(membership.sortOrder),
                    )
                }
            } catch {
                Logger.persistence.error("Core Data could not load recently closed workspaces for the active window. The app will continue, but recent workspace history could not be restored correctly. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
                return []
            }
        }
    }

    func countRecentWorkspaceHistory(for sceneIdentity: WorkspaceSceneIdentity) -> Int {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateLegacyRecentWorkspaceHistory(for: sceneIdentity, in: context)
                return try Self.loadRecentWorkspaceHistoryMemberships(
                    for: sceneIdentity,
                    in: context,
                )
                .count
            } catch {
                Logger.persistence.error("Core Data could not count recently closed workspaces for the active window. The app will continue, but command enablement may be stale. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
                return 0
            }
        }
    }

    func recordWorkspaceInRecentHistory(
        _ recentWorkspace: WindowWorkspaceHistoryInput,
        for sceneIdentity: WorkspaceSceneIdentity,
        limit: Int,
    ) {
        let context = container.viewContext
        context.performAndWait {
            do {
                try Self.migrateLegacyRecentWorkspaceHistory(for: sceneIdentity, in: context)
                let existingWorkspaceRequest = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
                var existingWorkspacesByID = try Dictionary(
                    uniqueKeysWithValues: context.fetch(existingWorkspaceRequest).map { ($0.id, $0) },
                )
                let now = Date()

                let workspaceEntity = try Self.upsertWorkspaceEntity(
                    for: recentWorkspace.workspace,
                    context: context,
                    existingWorkspacesByID: &existingWorkspacesByID,
                    sessionSnapshots: Self.makeSessionSnapshots(
                        for: recentWorkspace.workspace,
                        launchConfigurationsBySessionID: recentWorkspace.launchConfigurationsBySessionID,
                        titlesBySessionID: recentWorkspace.titlesBySessionID,
                        historyBySessionID: recentWorkspace.historyBySessionID,
                    ),
                    browserSessionSnapshots: Array(recentWorkspace.browserSnapshotsBySessionID.values),
                    now: now,
                )
                try Self.upsertWindowWorkspaceMembership(
                    windowID: sceneIdentity.windowID,
                    workspaceID: workspaceEntity.id,
                    sortOrder: Int64(recentWorkspace.formerIndex),
                    in: context,
                    now: now,
                )

                let recentWorkspaces = try Self.loadRecentWorkspaceHistoryMemberships(
                    for: sceneIdentity,
                    in: context,
                )
                if recentWorkspaces.count > limit {
                    for staleMembership in recentWorkspaces.dropFirst(limit).map(\.0) {
                        context.delete(staleMembership)
                    }
                }

                try Self.deleteOrphanedWorkspaceRecords(
                    existingWorkspacesByID: Dictionary(
                        uniqueKeysWithValues: context.fetch(existingWorkspaceRequest).map { ($0.id, $0) },
                    ),
                    retainedWorkspaceIDs: Self.retainedWorkspaceIDs(in: context),
                    context: context,
                )

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                Logger.persistence.error("Core Data could not record window-local recent workspace history for the active window. The live session remains available, but undo-close history was not persisted correctly. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Workspace ID: \(recentWorkspace.workspace.id.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
            }
        }
    }

    func consumeMostRecentWorkspaceInRecentHistory(
        for sceneIdentity: WorkspaceSceneIdentity,
    ) -> WindowWorkspaceHistoryRecord? {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateLegacyRecentWorkspaceHistory(for: sceneIdentity, in: context)
                guard let membershipAndWorkspace = try Self.loadRecentWorkspaceHistoryMemberships(
                    for: sceneIdentity,
                    in: context,
                )
                .first else {
                    return nil
                }

                let membership = membershipAndWorkspace.0
                let workspaceEntity = membershipAndWorkspace.1
                guard let revision = Self.workspaceRevision(for: workspaceEntity) else {
                    context.delete(membership)
                    if context.hasChanges {
                        try context.save()
                    }
                    return nil
                }

                let restoredWorkspace = WindowWorkspaceHistoryRecord(
                    revision: revision,
                    formerIndex: Int(membership.sortOrder),
                )
                context.delete(membership)
                try Self.deleteOrphanedWorkspaceRecords(
                    existingWorkspacesByID: Dictionary(
                        uniqueKeysWithValues: context.fetch(NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")).map { ($0.id, $0) },
                    ),
                    retainedWorkspaceIDs: Self.retainedWorkspaceIDs(in: context),
                    context: context,
                )
                if context.hasChanges {
                    try context.save()
                }
                return restoredWorkspace
            } catch {
                Logger.persistence.error("Core Data could not restore the most recently closed workspace for the active window. The app will continue, but undo close workspace could not complete. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
                return nil
            }
        }
    }

    func clearRecentWorkspaceHistory(for sceneIdentity: WorkspaceSceneIdentity) {
        let context = container.viewContext
        context.performAndWait {
            do {
                try Self.migrateLegacyRecentWorkspaceHistory(for: sceneIdentity, in: context)
                let recentWorkspaces = try Self.loadRecentWorkspaceHistoryMemberships(
                    for: sceneIdentity,
                    in: context,
                )
                for membership in recentWorkspaces.map(\.0) {
                    context.delete(membership)
                }

                try Self.deleteOrphanedWorkspaceRecords(
                    existingWorkspacesByID: Dictionary(
                        uniqueKeysWithValues: context.fetch(NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")).map { ($0.id, $0) },
                    ),
                    retainedWorkspaceIDs: Self.retainedWorkspaceIDs(in: context),
                    context: context,
                )
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                Logger.persistence.error("Core Data could not clear recently closed workspaces for the active window. The app will continue, but stale undo-close history may remain visible. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
            }
        }
    }

    func removeWorkspaceFromWindowHistory(
        _ workspaceID: WorkspaceID,
        for sceneIdentity: WorkspaceSceneIdentity,
    ) {
        let context = container.viewContext
        context.performAndWait {
            do {
                try Self.migrateLegacyRecentWorkspaceHistory(for: sceneIdentity, in: context)
                let memberships = try Self.loadWindowWorkspaceMemberships(windowID: sceneIdentity.windowID, in: context)
                    .filter { $0.workspaceID == workspaceID.rawValue }
                for membership in memberships {
                    context.delete(membership)
                }

                try Self.deleteOrphanedWorkspaceRecords(
                    existingWorkspacesByID: Dictionary(
                        uniqueKeysWithValues: context.fetch(NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")).map { ($0.id, $0) },
                    ),
                    retainedWorkspaceIDs: Self.retainedWorkspaceIDs(in: context),
                    context: context,
                )
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                Logger.persistence.error("Core Data could not remove workspace history membership for a closed workspace. The app will continue, but recently closed workspace state may be stale. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
            }
        }
    }

    func loadWindowState(for sceneIdentity: WorkspaceSceneIdentity) -> WorkspaceWindowStateSnapshot? {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateLegacyWindowState(for: sceneIdentity, in: context)
                guard let window = try Self.loadWindowEntity(id: sceneIdentity.windowID, in: context) else {
                    return nil
                }

                let selectedWorkspaceID = window.selectedWorkspaceID.map(WorkspaceID.init(rawValue:))
                let selectedPaneID = window.selectedPaneID.map(PaneID.init(rawValue:))
                return WorkspaceWindowStateSnapshot(
                    selectedWorkspaceID: selectedWorkspaceID,
                    selectedPaneID: selectedPaneID,
                )
            } catch {
                Logger.persistence.error(
                    "Core Data could not load the durable window metadata for the active workspace scene. The app will continue, but this window may fall back to lighter-weight restoration behavior. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)",
                )
                context.rollback()
                return nil
            }
        }
    }

    func loadLiveSceneIdentities(
        matching sceneIdentities: [WorkspaceSceneIdentity]? = nil,
    ) -> [WorkspaceSceneIdentity] {
        let context = container.viewContext
        return context.performAndWait {
            do {
                if let sceneIdentities {
                    try Self.migrateLegacyWindowStateIfNeeded(
                        preferredSceneIdentities: sceneIdentities,
                        in: context,
                    )
                } else {
                    try Self.migrateAllLegacyWindowState(in: context)
                }
                let orderedPersistedSceneIdentities = try Self.loadWindowEntities(
                    matching: sceneIdentities?.map(\.windowID),
                    isOpen: true,
                    in: context,
                )
                .map { WorkspaceSceneIdentity(windowID: $0.id) }

                guard let sceneIdentities, !sceneIdentities.isEmpty else {
                    return orderedPersistedSceneIdentities
                }

                let persistedSceneIdentityByWindowID = Dictionary(
                    uniqueKeysWithValues: orderedPersistedSceneIdentities.map { ($0.windowID, $0) },
                )
                return sceneIdentities.compactMap { persistedSceneIdentityByWindowID[$0.windowID] }
            } catch {
                Logger.persistence.error(
                    "Core Data could not load the list of live workspace window identities for launch restoration. The app will continue, but it may reopen fewer windows than were present in the previous session. Error: \(String(describing: error), privacy: .public)",
                )
                context.rollback()
                return []
            }
        }
    }

    func loadRecentlyClosedWindowSceneIdentities() -> [WorkspaceSceneIdentity] {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateAllLegacyWindowState(in: context)
                return try Self.loadWindowEntities(matching: nil, isOpen: false, in: context)
                    .map { WorkspaceSceneIdentity(windowID: $0.id) }
            } catch {
                Logger.persistence.error(
                    "Core Data could not load recently closed windows for restoration commands. The app will continue, but Open Recent Window may be unavailable until window persistence loads correctly. Error: \(String(describing: error), privacy: .public)",
                )
                context.rollback()
                return []
            }
        }
    }

    func markWindowOpen(_ sceneIdentity: WorkspaceSceneIdentity, title: String? = nil, selectedWorkspaceID: WorkspaceID? = nil) {
        updateWindowRecord(
            for: sceneIdentity,
            title: title,
            selectedWorkspaceID: selectedWorkspaceID,
            isOpen: true,
        )
    }

    func markWindowClosed(_ sceneIdentity: WorkspaceSceneIdentity, saveToLibrary: Bool) {
        updateWindowRecord(
            for: sceneIdentity,
            title: nil,
            selectedWorkspaceID: nil,
            isOpen: false,
            saveToLibrary: saveToLibrary,
        )
    }

    func saveSceneState(
        for sceneIdentity: WorkspaceSceneIdentity,
        liveWorkspaces: [Workspace],
        selectedWorkspaceID: WorkspaceID?,
        selectedPaneID: PaneID?,
        sessions: TerminalSessionRegistry,
        browserSessions: BrowserSessionRegistry,
        liveHistoryByWorkspaceID: [WorkspaceID: [TerminalSessionID: WorkspaceSessionHistorySnapshot]] = [:],
        liveBrowserSnapshotsByWorkspaceID: [WorkspaceID: [BrowserSessionID: BrowserSessionSnapshot]] = [:],
    ) {
        let liveSessionSnapshotsByWorkspaceID = Dictionary(
            uniqueKeysWithValues: liveWorkspaces.map { workspace in
                (
                    workspace.id,
                    Self.makeSessionSnapshots(
                        for: workspace,
                        sessions: sessions,
                        historyBySessionID: liveHistoryByWorkspaceID[workspace.id] ?? [:],
                    ),
                )
            },
        )
        let resolvedBrowserSnapshotsByWorkspaceID = Dictionary(
            uniqueKeysWithValues: liveWorkspaces.map { workspace in
                (
                    workspace.id,
                    Self.makeBrowserSessionSnapshots(
                        for: workspace,
                        browserSessions: browserSessions,
                        browserSnapshotsBySessionID: liveBrowserSnapshotsByWorkspaceID[workspace.id] ?? [:],
                    ),
                )
            },
        )
        let context = container.viewContext
        context.performAndWait {
            do {
                try Self.migrateLegacyRecentWorkspaceHistory(for: sceneIdentity, in: context)
                let livePlacements = Self.loadPlacements(role: .live, sceneIdentity: sceneIdentity, in: context)
                var existingPlacementsByID = Dictionary(uniqueKeysWithValues: livePlacements.map { ($0.id, $0) })
                let existingWorkspaceRequest = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
                let existingWorkspaces = try context.fetch(existingWorkspaceRequest)
                var existingWorkspacesByID = Dictionary(uniqueKeysWithValues: existingWorkspaces.map { ($0.id, $0) })
                var retainedPlacementIDs: Set<UUID> = []

                for (sortOrder, workspace) in liveWorkspaces.enumerated() {
                    let workspaceEntity = try Self.upsertWorkspaceEntity(
                        for: workspace,
                        context: context,
                        existingWorkspacesByID: &existingWorkspacesByID,
                        sessionSnapshots: liveSessionSnapshotsByWorkspaceID[workspace.id] ?? [],
                        browserSessionSnapshots: resolvedBrowserSnapshotsByWorkspaceID[workspace.id] ?? [],
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
                    Self.refreshLivePlacementMetadata(on: placement, from: workspaceEntity)
                    retainedPlacementIDs.insert(placement.id)
                    try Self.upsertWindowWorkspaceMembership(
                        windowID: sceneIdentity.windowID,
                        workspaceID: workspace.id.rawValue,
                        sortOrder: Int64(sortOrder),
                        in: context,
                        now: now,
                    )
                }

                for stalePlacement in existingPlacementsByID.values where !retainedPlacementIDs.contains(stalePlacement.id) {
                    context.delete(stalePlacement)
                }

                let now = Date()
                try Self.migrateLegacyWindowState(for: sceneIdentity, in: context)
                let window = try Self.requireOrCreateWindowEntity(id: sceneIdentity.windowID, context: context)
                if window.objectID.isTemporaryID {
                    window.id = sceneIdentity.windowID
                    window.createdAt = now
                }
                window.updatedAt = now
                window.lastActiveAt = now
                window.selectedWorkspaceID = selectedWorkspaceID?.rawValue
                window.selectedPaneID = selectedPaneID?.rawValue
                window.title = selectedWorkspaceID
                    .flatMap { workspaceID in liveWorkspaces.first { $0.id == workspaceID }?.title }
                    ?? liveWorkspaces.first?.title
                window.isOpen = true

                try Self.deleteOrphanedWorkspaceRecords(
                    existingWorkspacesByID: existingWorkspacesByID,
                    retainedWorkspaceIDs: Self.retainedWorkspaceIDs(in: context),
                    context: context,
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

    func listLibraryItems(matching query: String? = nil) -> [LibraryItemListing] {
        let context = container.viewContext
        let trimmedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines)

        return context.performAndWait {
            do {
                try Self.migrateLegacyLibraryItems(in: context)
                return try Self.loadLibraryItems(matching: trimmedQuery, in: context)
                    .filter { item in
                        switch item.kind {
                            case .workspace:
                                guard let workspaceID = item.workspaceID else {
                                    return false
                                }

                                return !Self.isWorkspaceLive(workspaceID: workspaceID.rawValue, in: context)
                            case .window:
                                guard let sceneIdentity = item.windowID else {
                                    return false
                                }

                                return !Self.isWindowOpen(windowID: sceneIdentity.windowID, in: context)
                        }
                    }
            } catch {
                Logger.persistence.error("Core Data failed to list library items. The app will continue, but the library index could not be read. Error: \(String(describing: error), privacy: .public)")
                return []
            }
        }
    }

    func upsertWorkspaceLibraryItem(
        from workspace: Workspace,
        sessions: TerminalSessionRegistry,
        browserSessions: BrowserSessionRegistry,
        historyBySessionID: [TerminalSessionID: WorkspaceSessionHistorySnapshot] = [:],
        browserSnapshotsBySessionID: [BrowserSessionID: BrowserSessionSnapshot] = [:],
        notes: String? = nil,
        isPinned: Bool? = nil,
    ) -> LibraryItemListing? {
        let sessionSnapshots = Self.makeSessionSnapshots(
            for: workspace,
            sessions: sessions,
            historyBySessionID: historyBySessionID,
        )
        let browserSessionSnapshots = Self.makeBrowserSessionSnapshots(
            for: workspace,
            browserSessions: browserSessions,
            browserSnapshotsBySessionID: browserSnapshotsBySessionID,
        )
        let context = container.viewContext
        return context.performAndWait {
            do {
                let now = Date()
                let workspaceEntity = try Self.requireOrCreateWorkspaceEntity(
                    id: workspace.id.rawValue,
                    context: context,
                )
                try Self.updateWorkspaceEntity(
                    workspaceEntity,
                    from: workspace,
                    context: context,
                    sessionSnapshots: sessionSnapshots,
                    browserSessionSnapshots: browserSessionSnapshots,
                    notes: notes,
                    now: now,
                )
                let libraryItem = try Self.requireOrCreateLibraryItem(
                    kind: .workspace,
                    workspaceID: workspace.id.rawValue,
                    context: context,
                )
                if libraryItem.objectID.isTemporaryID {
                    libraryItem.createdAt = now
                }
                libraryItem.kind = LibraryItemKind.workspace.rawValue
                libraryItem.workspaceID = workspace.id.rawValue
                libraryItem.windowID = nil
                libraryItem.updatedAt = now
                libraryItem.isPinned = isPinned ?? libraryItem.isPinned
                Self.refreshListingMetadata(on: libraryItem, from: workspaceEntity)

                if context.hasChanges {
                    try context.save()
                }

                return Self.makeLibraryItemListing(from: libraryItem)
            } catch {
                Logger.persistence.error("Core Data failed to save a workspace revision into the library. The live workspace remains available, but the saved copy was not written. Workspace title: \(workspace.title, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
                return nil
            }
        }
    }

    func saveWorkspaceToLibrary(
        from workspace: Workspace,
        sessions: TerminalSessionRegistry,
        browserSessions: BrowserSessionRegistry,
        historyBySessionID: [TerminalSessionID: WorkspaceSessionHistorySnapshot] = [:],
        browserSnapshotsBySessionID: [BrowserSessionID: BrowserSessionSnapshot] = [:],
        notes: String? = nil,
        isPinned: Bool? = nil,
    ) -> LibraryItemListing? {
        upsertWorkspaceLibraryItem(
            from: workspace,
            sessions: sessions,
            browserSessions: browserSessions,
            historyBySessionID: historyBySessionID,
            browserSnapshotsBySessionID: browserSnapshotsBySessionID,
            notes: notes,
            isPinned: isPinned,
        )
    }

    func loadWorkspaceLibraryItem(id: UUID) -> WorkspaceRevision? {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateLegacyLibraryItems(in: context)
                guard let libraryItem = try Self.loadLibraryItem(id: id, in: context) else {
                    Logger.persistence.error("The library could not find the requested entry during workspace reopen. The entry may have been deleted, or the selection may be stale. Library item ID: \(id.uuidString, privacy: .public)")
                    return nil
                }
                guard libraryItem.kind == LibraryItemKind.workspace.rawValue,
                      let workspaceID = libraryItem.workspaceID
                else {
                    Logger.persistence.error("The library entry requested for workspace reopen did not point at a workspace payload. Library item ID: \(id.uuidString, privacy: .public). Kind: \(libraryItem.kind, privacy: .public)")
                    return nil
                }

                return try Self.workspaceRevision(
                    for: Self.loadWorkspaceEntity(id: workspaceID, in: context),
                    lastOpenedAt: libraryItem.lastOpenedAt,
                    isPinned: libraryItem.isPinned,
                )
            } catch {
                Logger.persistence.error("Core Data failed while reading a workspace library item. The requested entry could not be loaded. Library item ID: \(id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    func loadLibraryItemListing(id: UUID) -> LibraryItemListing? {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateLegacyLibraryItems(in: context)
                return try Self.loadLibraryItem(id: id, in: context)
                    .flatMap(Self.makeLibraryItemListing(from:))
            } catch {
                Logger.persistence.error("Core Data failed while reading a library item listing. The requested entry could not be loaded. Library item ID: \(id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    @discardableResult
    func deleteLibraryItem(id: UUID) -> Bool {
        let context = container.viewContext
        return context.performAndWait {
            do {
                try Self.migrateLegacyLibraryItems(in: context)
                guard let libraryItem = try Self.loadLibraryItem(id: id, in: context) else {
                    Logger.persistence.error("The library could not find the entry requested for deletion. The library may already be up to date, or the selection may have gone stale. Library item ID: \(id.uuidString, privacy: .public)")
                    return false
                }

                let libraryWorkspaceID = libraryItem.workspaceID
                context.delete(libraryItem)

                if let libraryWorkspaceID {
                    try Self.deleteOrphanedWorkspaceRecords(
                        existingWorkspacesByID: [libraryWorkspaceID: Self.requireWorkspaceEntity(id: libraryWorkspaceID, context: context)],
                        retainedWorkspaceIDs: Self.retainedWorkspaceIDs(in: context),
                        context: context,
                    )
                }

                if context.hasChanges {
                    try context.save()
                }
                return true
            } catch {
                Logger.persistence.error("Core Data failed to delete a library item. The entry remains available. Library item ID: \(id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
                return false
            }
        }
    }

    func markLibraryItemOpened(_ id: UUID) {
        let context = container.viewContext
        context.performAndWait {
            do {
                try Self.migrateLegacyLibraryItems(in: context)
                guard let libraryItem = try Self.loadLibraryItem(id: id, in: context) else {
                    return
                }

                let now = Date()
                libraryItem.lastOpenedAt = now
                libraryItem.updatedAt = now
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                Logger.persistence.error("Core Data failed to update the recency metadata for a library item. The entry remains usable, but its last-opened date is stale. Library item ID: \(id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                context.rollback()
            }
        }
    }
}

extension WorkspacePersistenceController {
    private func updateWindowRecord(
        for sceneIdentity: WorkspaceSceneIdentity,
        title: String?,
        selectedWorkspaceID: WorkspaceID?,
        selectedPaneID: PaneID? = nil,
        isOpen: Bool,
        saveToLibrary: Bool = false,
    ) {
        let context = container.viewContext
        context.performAndWait {
            do {
                try Self.migrateLegacyWindowState(for: sceneIdentity, in: context)
                let now = Date()
                let window = try Self.requireOrCreateWindowEntity(id: sceneIdentity.windowID, context: context)
                if window.objectID.isTemporaryID {
                    window.id = sceneIdentity.windowID
                    window.createdAt = now
                }
                window.updatedAt = now
                window.lastActiveAt = now
                if let selectedWorkspaceID {
                    window.selectedWorkspaceID = selectedWorkspaceID.rawValue
                }
                if let selectedPaneID {
                    window.selectedPaneID = selectedPaneID.rawValue
                }
                if let title {
                    window.title = title
                }
                window.isOpen = isOpen
                if !isOpen, saveToLibrary {
                    _ = try Self.upsertWindowLibraryItem(for: sceneIdentity, in: context, now: now)
                }
                if context.hasChanges {
                    try context.save()
                }
            } catch {
                Logger.persistence.error(
                    "Core Data could not update the durable window record for the active workspace scene. Window restore behavior may be stale until the next successful save. Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Open state: \(isOpen, privacy: .public). Error: \(String(describing: error), privacy: .public)",
                )
                context.rollback()
            }
        }
    }

    private nonisolated static func loadPlacements(
        role: WorkspacePlacementRole,
        sceneIdentity: WorkspaceSceneIdentity,
        in context: NSManagedObjectContext,
    ) -> [WorkspacePlacementEntity] {
        let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
        request.sortDescriptors = [NSSortDescriptor(key: #keyPath(WorkspacePlacementEntity.sortOrder), ascending: true)]
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "role == %@", role.rawValue),
                NSPredicate(format: "windowID == %@", sceneIdentity.windowID as CVarArg),
            ],
        )

        do {
            return try context.fetch(request)
        } catch {
            Logger.persistence.error("Core Data failed to fetch workspace placements for scene restoration. Role: \(role.rawValue, privacy: .public). Window ID: \(sceneIdentity.windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private nonisolated static func upsertWorkspaceEntity(
        for workspace: Workspace,
        context: NSManagedObjectContext,
        existingWorkspacesByID: inout [UUID: WorkspaceEntity],
        sessionSnapshots: [WorkspaceSessionSnapshot],
        browserSessionSnapshots: [BrowserSessionSnapshot],
        now: Date = Date(),
    ) throws -> WorkspaceEntity {
        let workspaceEntity = existingWorkspacesByID.removeValue(forKey: workspace.id.rawValue)
            ?? WorkspaceEntity(context: context)
        workspaceEntity.id = workspace.id.rawValue
        try updateWorkspaceEntity(
            workspaceEntity,
            from: workspace,
            context: context,
            sessionSnapshots: sessionSnapshots,
            browserSessionSnapshots: browserSessionSnapshots,
            notes: workspaceEntity.notes,
            now: now,
        )
        return workspaceEntity
    }

    private nonisolated static func updateWorkspaceEntity(
        _ workspaceEntity: WorkspaceEntity,
        from workspace: Workspace,
        context: NSManagedObjectContext,
        sessionSnapshots: [WorkspaceSessionSnapshot],
        browserSessionSnapshots: [BrowserSessionSnapshot],
        notes: String?,
        now: Date,
    ) throws {
        let isNewRecord = workspaceEntity.objectID.isTemporaryID
        if isNewRecord {
            workspaceEntity.createdAt = now
        }
        workspaceEntity.updatedAt = now
        workspaceEntity.lastActiveAt = now
        workspaceEntity.recentWindowID = nil
        workspaceEntity.recentSortOrder = 0
        workspaceEntity.title = workspace.title
        workspaceEntity.notes = notes
        workspaceEntity.sortOrder = 0
        if let existingRootNode = workspaceEntity.rootNode {
            context.delete(existingRootNode)
        }
        for existingSessionSnapshot in (workspaceEntity.sessionSnapshots as? Set<PaneSessionSnapshotEntity>) ?? [] {
            context.delete(existingSessionSnapshot)
        }
        for existingBrowserSessionSnapshot in (workspaceEntity.browserSessionSnapshots as? Set<BrowserPaneSessionSnapshotEntity>) ?? [] {
            context.delete(existingBrowserSessionSnapshot)
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
            entity.normalScrollPosition = sessionSnapshot.normalScrollPosition ?? 0
            entity.hasNormalScrollPosition = sessionSnapshot.normalScrollPosition != nil
            entity.wasAlternateBufferActive = sessionSnapshot.wasAlternateBufferActive
            entity.transcriptByteCount = Int64(sessionSnapshot.transcriptByteCount)
            entity.transcriptLineCount = Int64(sessionSnapshot.transcriptLineCount)
            entity.previewText = sessionSnapshot.previewText
            entity.workspace = workspaceEntity
            return entity
        }
        let browserSessionSnapshotEntities = browserSessionSnapshots.map { sessionSnapshot -> BrowserPaneSessionSnapshotEntity in
            let entity = BrowserPaneSessionSnapshotEntity(context: context)
            entity.id = sessionSnapshot.id.rawValue
            entity.title = sessionSnapshot.title
            entity.url = sessionSnapshot.url
            entity.lastCommittedURL = sessionSnapshot.lastCommittedURL
            entity.state = sessionSnapshot.state.rawValue
            entity.failureDescription = sessionSnapshot.failureDescription
            entity.previewText = sessionSnapshot.previewText
            entity.historyURLsData = try? JSONEncoder().encode(sessionSnapshot.history?.items.map(\.url))
            entity.historyTitlesData = try? JSONEncoder().encode(sessionSnapshot.history?.items.map(\.title))
            entity.hasHistory = sessionSnapshot.history != nil
            entity.historyCurrentIndex = Int64(sessionSnapshot.history?.currentIndex ?? 0)
            entity.workspace = workspaceEntity
            return entity
        }
        workspaceEntity.sessionSnapshots = NSSet(array: sessionSnapshotEntities)
        workspaceEntity.browserSessionSnapshots = NSSet(array: browserSessionSnapshotEntities)
        workspaceEntity.previewText = sessionSnapshots.lazy.compactMap(\.previewText).first
            ?? browserSessionSnapshots.lazy.compactMap(\.previewText).first
        workspaceEntity.searchText = makeSearchText(
            title: workspace.title,
            notes: notes,
            previewText: workspaceEntity.previewText,
            sessionSnapshots: sessionSnapshots,
            browserSessionSnapshots: browserSessionSnapshots,
        )
    }

    private static func makeSessionSnapshots(
        for workspace: Workspace,
        sessions: TerminalSessionRegistry,
        historyBySessionID: [TerminalSessionID: WorkspaceSessionHistorySnapshot],
    ) -> [WorkspaceSessionSnapshot] {
        makeSessionSnapshots(
            for: workspace,
            launchConfigurationsBySessionID: Dictionary(
                uniqueKeysWithValues: (workspace.root?.leaves() ?? []).compactMap { leaf in
                    guard let sessionID = leaf.terminalSessionID else {
                        return nil
                    }

                    let session = sessions.ensureSession(id: sessionID)
                    let launchConfiguration = TerminalLaunchConfiguration(
                        executable: session.launchConfiguration.executable,
                        arguments: session.launchConfiguration.arguments,
                        environment: session.launchConfiguration.environment,
                        currentDirectory: session.currentDirectory ?? session.launchConfiguration.currentDirectory,
                    )
                    return (sessionID, launchConfiguration)
                },
            ),
            titlesBySessionID: Dictionary(
                uniqueKeysWithValues: (workspace.root?.leaves() ?? []).compactMap { leaf in
                    guard let sessionID = leaf.terminalSessionID else {
                        return nil
                    }

                    let session = sessions.ensureSession(id: sessionID)
                    return (sessionID, session.title)
                },
            ),
            historyBySessionID: historyBySessionID,
        )
    }

    private static func makeBrowserSessionSnapshots(
        for workspace: Workspace,
        browserSessions: BrowserSessionRegistry,
        browserSnapshotsBySessionID: [BrowserSessionID: BrowserSessionSnapshot],
    ) -> [BrowserSessionSnapshot] {
        (workspace.root?.leaves() ?? []).compactMap { leaf in
            guard let sessionID = leaf.browserSessionID else {
                return nil
            }

            return browserSnapshotsBySessionID[sessionID]
                ?? browserSessions.session(for: sessionID)?.makeSnapshot()
        }
    }

    private nonisolated static func makeSessionSnapshots(
        for workspace: Workspace,
        launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration],
        titlesBySessionID: [TerminalSessionID: String],
        historyBySessionID: [TerminalSessionID: WorkspaceSessionHistorySnapshot],
    ) -> [WorkspaceSessionSnapshot] {
        (workspace.root?.leaves() ?? []).compactMap { leaf in
            guard let sessionID = leaf.terminalSessionID,
                  let launchConfiguration = launchConfigurationsBySessionID[sessionID]
            else {
                return nil
            }

            let history = historyBySessionID[sessionID]
                ?? WorkspaceSessionHistorySnapshot(
                    transcript: nil,
                    normalScrollPosition: nil,
                    wasAlternateBufferActive: false,
                )
            let transcript = history.transcript
            let transcriptLineCount = transcript.map { transcript in
                transcript.isEmpty ? 0 : transcript.reduce(into: 1) { count, character in
                    if character == "\n" {
                        count += 1
                    }
                }
            } ?? 0
            let previewText = transcript.flatMap(Self.makePreviewText(from:))
            return WorkspaceSessionSnapshot(
                id: sessionID,
                title: titlesBySessionID[sessionID] ?? "Shell",
                launchConfiguration: launchConfiguration,
                history: history,
                transcriptByteCount: transcript?.utf8.count ?? 0,
                transcriptLineCount: transcriptLineCount,
                previewText: previewText,
            )
        }
    }

    private nonisolated static func workspaceRevision(
        for workspaceEntity: WorkspaceEntity?,
        lastOpenedAt: Date? = nil,
        isPinned: Bool = false,
    ) -> WorkspaceRevision? {
        guard let workspaceEntity else {
            Logger.persistence.error("A workspace revision request is missing its referenced workspace payload. That payload will be skipped during restore.")
            return nil
        }

        let workspace = Workspace(
            id: WorkspaceID(rawValue: workspaceEntity.id),
            title: workspaceEntity.title,
            root: Self.decodeNode(workspaceEntity.rootNode),
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
        let browserSessionSnapshots = decodeBrowserSessionSnapshots(from: workspaceEntity)
        return WorkspaceRevision(
            id: workspaceEntity.id,
            title: workspaceEntity.title,
            createdAt: workspaceEntity.createdAt,
            updatedAt: workspaceEntity.updatedAt,
            lastActiveAt: workspaceEntity.lastActiveAt,
            lastOpenedAt: lastOpenedAt,
            isPinned: isPinned,
            notes: workspaceEntity.notes,
            previewText: workspaceEntity.previewText,
            workspace: Workspace(
                id: WorkspaceID(rawValue: workspaceEntity.id),
                title: workspace.title,
                root: root,
            ),
            paneSnapshotsBySessionID: sessionSnapshots,
            browserSnapshotsBySessionID: browserSessionSnapshots,
        )
    }

    private nonisolated static func decodeSessionSnapshots(from workspaceEntity: WorkspaceEntity) -> [TerminalSessionID: WorkspaceSessionSnapshot] {
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
                            currentDirectory: sessionSnapshot.currentDirectory,
                        ),
                        history: WorkspaceSessionHistorySnapshot(
                            transcript: sessionSnapshot.transcript,
                            normalScrollPosition: sessionSnapshot.hasNormalScrollPosition
                                ? sessionSnapshot.normalScrollPosition
                                : nil,
                            wasAlternateBufferActive: sessionSnapshot.wasAlternateBufferActive,
                        ),
                        transcriptByteCount: Int(sessionSnapshot.transcriptByteCount),
                        transcriptLineCount: Int(sessionSnapshot.transcriptLineCount),
                        previewText: sessionSnapshot.previewText,
                    )
                    return (sessionSnapshotValue.id, sessionSnapshotValue)
                } catch {
                    Logger.persistence.error("A persisted pane session payload could not be decoded. That pane payload will be skipped during restore. Session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
                    return nil
                }
            },
        )
    }

    private nonisolated static func decodeBrowserSessionSnapshots(from workspaceEntity: WorkspaceEntity) -> [BrowserSessionID: BrowserSessionSnapshot] {
        let snapshotEntities = workspaceEntity.browserSessionSnapshots as? Set<BrowserPaneSessionSnapshotEntity> ?? []
        return Dictionary(
            uniqueKeysWithValues: snapshotEntities.compactMap { sessionSnapshot in
                guard let state = BrowserSessionSnapshotState(rawValue: sessionSnapshot.state) else {
                    Logger.persistence.error("A persisted browser pane session payload has an invalid state value. That browser payload will be skipped during restore. Browser session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public)")
                    return nil
                }

                let snapshot = BrowserSessionSnapshot(
                    id: BrowserSessionID(rawValue: sessionSnapshot.id),
                    title: sessionSnapshot.title,
                    url: sessionSnapshot.url,
                    lastCommittedURL: sessionSnapshot.lastCommittedURL,
                    state: state,
                    failureDescription: sessionSnapshot.failureDescription,
                    previewText: sessionSnapshot.previewText,
                    history: decodeBrowserHistorySnapshot(from: sessionSnapshot),
                )
                return (snapshot.id, snapshot)
            },
        )
    }

    private nonisolated static func decodeBrowserHistorySnapshot(
        from sessionSnapshot: BrowserPaneSessionSnapshotEntity,
    ) -> BrowserSessionHistorySnapshot? {
        guard sessionSnapshot.hasHistory else {
            return nil
        }
        guard let historyURLsData = sessionSnapshot.historyURLsData else {
            Logger.persistence.error("A persisted browser pane history payload is missing its URL list. That browser history will be skipped during restore, but the browser session itself will still load. Browser session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public)")
            return nil
        }

        do {
            let urls = try JSONDecoder().decode([String].self, from: historyURLsData)
            let titles = try sessionSnapshot.historyTitlesData.map {
                try JSONDecoder().decode([String?].self, from: $0)
            } ?? Array(repeating: nil, count: urls.count)
            guard urls.count == titles.count else {
                Logger.persistence.error("A persisted browser pane history payload has mismatched URL and title counts. That browser history will be skipped during restore, but the browser session itself will still load. Browser session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public)")
                return nil
            }

            let currentIndex = Int(sessionSnapshot.historyCurrentIndex)
            guard urls.indices.contains(currentIndex) else {
                Logger.persistence.error("A persisted browser pane history payload has an invalid current index. That browser history will be skipped during restore, but the browser session itself will still load. Browser session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public). Current index: \(currentIndex)")
                return nil
            }

            return BrowserSessionHistorySnapshot(
                items: zip(urls, titles).map { url, title in
                    BrowserHistoryItemSnapshot(url: url, title: title)
                },
                currentIndex: currentIndex,
            )
        } catch {
            Logger.persistence.error("A persisted browser pane history payload could not be decoded. That browser history will be skipped during restore, but the browser session itself will still load. Browser session payload ID: \(sessionSnapshot.id.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private nonisolated static func refreshLivePlacementMetadata(on placement: WorkspacePlacementEntity, from workspaceEntity: WorkspaceEntity) {
        placement.title = workspaceEntity.title
        placement.previewText = workspaceEntity.previewText
        placement.searchText = workspaceEntity.searchText
        placement.paneCount = Int64(decodeNode(workspaceEntity.rootNode)?.leaves().count ?? 0)
    }

    private nonisolated static func refreshListingMetadata(on libraryItem: LibraryItemEntity, from workspaceEntity: WorkspaceEntity) {
        libraryItem.title = workspaceEntity.title
        libraryItem.previewText = workspaceEntity.previewText
        libraryItem.searchText = workspaceEntity.searchText
        libraryItem.paneCount = Int64(decodeNode(workspaceEntity.rootNode)?.leaves().count ?? 0)
        libraryItem.workspaceCount = 1
    }

    private nonisolated static func refreshListingMetadata(
        on libraryItem: LibraryItemEntity,
        from windowEntity: WorkspaceWindowEntity,
        livePlacements: [WorkspacePlacementEntity],
    ) {
        let orderedWorkspaceEntities = livePlacements.compactMap(\.workspace)
        let selectedWorkspaceEntity = windowEntity.selectedWorkspaceID.flatMap { selectedWorkspaceID in
            orderedWorkspaceEntities.first { $0.id == selectedWorkspaceID }
        }
        let representativeWorkspaceEntity = selectedWorkspaceEntity ?? orderedWorkspaceEntities.first
        let trimmedWindowTitle = windowEntity.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = if let trimmedWindowTitle, !trimmedWindowTitle.isEmpty {
            trimmedWindowTitle
        } else if let selectedWorkspaceEntity {
            selectedWorkspaceEntity.title
        } else if let representativeWorkspaceEntity {
            representativeWorkspaceEntity.title
        } else {
            "Window"
        }
        let paneCount = orderedWorkspaceEntities.reduce(into: 0) { count, workspaceEntity in
            count += decodeNode(workspaceEntity.rootNode)?.leaves().count ?? 0
        }
        let previewText = representativeWorkspaceEntity?.previewText
        let searchText = (
            [resolvedTitle, previewText, representativeWorkspaceEntity?.searchText]
                + orderedWorkspaceEntities.map(\.title).map(Optional.some)
                + orderedWorkspaceEntities.compactMap(\.previewText).map(Optional.some),
        )
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")

        libraryItem.title = resolvedTitle
        libraryItem.previewText = previewText
        libraryItem.searchText = searchText
        libraryItem.paneCount = Int64(paneCount)
        libraryItem.workspaceCount = Int64(orderedWorkspaceEntities.count)
    }

    private nonisolated static func makeLibraryItemListing(from libraryItem: LibraryItemEntity) -> LibraryItemListing? {
        guard let kind = LibraryItemKind(rawValue: libraryItem.kind) else {
            return nil
        }

        return LibraryItemListing(
            id: libraryItem.id,
            kind: kind,
            workspaceID: libraryItem.workspaceID.map { WorkspaceID(rawValue: $0) },
            windowID: libraryItem.windowID.map { WorkspaceSceneIdentity(windowID: $0) },
            title: libraryItem.title,
            createdAt: libraryItem.createdAt,
            updatedAt: libraryItem.updatedAt,
            lastOpenedAt: libraryItem.lastOpenedAt,
            isPinned: libraryItem.isPinned,
            previewText: libraryItem.previewText,
            paneCount: Int(libraryItem.paneCount),
            workspaceCount: Int(libraryItem.workspaceCount),
        )
    }

    private nonisolated static func makeSearchText(
        title: String,
        notes: String?,
        previewText: String?,
        sessionSnapshots: [WorkspaceSessionSnapshot],
        browserSessionSnapshots: [BrowserSessionSnapshot],
    ) -> String {
        let pieces = [title, notes, previewText]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let transcriptPieces = sessionSnapshots.compactMap(\.transcript).filter { !$0.isEmpty }
        let browserPieces = browserSessionSnapshots.flatMap { snapshot in
            [snapshot.title, snapshot.lastCommittedURL ?? snapshot.url].compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        .filter { !$0.isEmpty }
        return (pieces + transcriptPieces + browserPieces).joined(separator: "\n")
    }

    private nonisolated static func deleteOrphanedWorkspaceRecords(
        existingWorkspacesByID: [UUID: WorkspaceEntity],
        retainedWorkspaceIDs: Set<UUID>,
        context: NSManagedObjectContext,
    ) throws {
        for workspaceEntity in existingWorkspacesByID.values where !retainedWorkspaceIDs.contains(workspaceEntity.id) {
            let hasLegacyRecentAssociation = workspaceEntity.recentWindowID != nil
            let livePlacements = (workspaceEntity.placements as? Set<WorkspacePlacementEntity>) ?? []
            let hasLiveReference = livePlacements.contains { placement in
                guard !placement.isDeleted else {
                    return false
                }
                guard let role = WorkspacePlacementRole(rawValue: placement.role) else {
                    return false
                }

                return role == .live
            }
            let hasWindowMembership = try !loadWindowWorkspaceMemberships(
                workspaceID: workspaceEntity.id,
                in: context,
            ).isEmpty
            guard !hasLiveReference, !hasWindowMembership, !hasLegacyRecentAssociation else {
                continue
            }

            context.delete(workspaceEntity)
        }
    }

    private nonisolated static func loadRecentWorkspaceHistoryMemberships(
        for sceneIdentity: WorkspaceSceneIdentity,
        in context: NSManagedObjectContext,
    ) throws -> [(WindowWorkspaceMembershipEntity, WorkspaceEntity)] {
        let liveWorkspaceIDs = Set(loadPlacements(role: .live, sceneIdentity: sceneIdentity, in: context).compactMap(\.workspace?.id))
        return try loadWindowWorkspaceMemberships(windowID: sceneIdentity.windowID, in: context)
            .compactMap { membership in
                guard !liveWorkspaceIDs.contains(membership.workspaceID) else {
                    return nil
                }
                guard let workspace = try loadWorkspaceEntity(id: membership.workspaceID, in: context) else {
                    return nil
                }

                return (membership, workspace)
            }
            .sorted { lhs, rhs in
                let leftWorkspace = lhs.1
                let rightWorkspace = rhs.1
                if leftWorkspace.lastActiveAt != rightWorkspace.lastActiveAt {
                    return leftWorkspace.lastActiveAt > rightWorkspace.lastActiveAt
                }
                if leftWorkspace.updatedAt != rightWorkspace.updatedAt {
                    return leftWorkspace.updatedAt > rightWorkspace.updatedAt
                }
                return lhs.0.updatedAt > rhs.0.updatedAt
            }
    }

    private nonisolated static func migrateLegacyRecentWorkspaceHistory(
        for sceneIdentity: WorkspaceSceneIdentity,
        in context: NSManagedObjectContext,
    ) throws {
        let workspaceRequest = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
        workspaceRequest.predicate = NSPredicate(format: "recentWindowID == %@", sceneIdentity.windowID as CVarArg)
        let workspaceEntities = try context.fetch(workspaceRequest)
        for workspaceEntity in workspaceEntities {
            try upsertWindowWorkspaceMembership(
                windowID: sceneIdentity.windowID,
                workspaceID: workspaceEntity.id,
                sortOrder: workspaceEntity.recentSortOrder,
                in: context,
                now: workspaceEntity.updatedAt,
            )
            workspaceEntity.recentWindowID = nil
            workspaceEntity.recentSortOrder = 0
        }

        let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "role == %@", WorkspacePersistenceLegacy.recentPlacementRoleRawValue),
                NSPredicate(format: "windowID == %@", sceneIdentity.windowID as CVarArg),
            ],
        )
        let legacyPlacements = try context.fetch(request)
        guard !legacyPlacements.isEmpty else {
            return
        }

        for placement in legacyPlacements {
            guard let workspaceEntity = placement.workspace else {
                context.delete(placement)
                continue
            }

            try upsertWindowWorkspaceMembership(
                windowID: sceneIdentity.windowID,
                workspaceID: workspaceEntity.id,
                sortOrder: placement.restoreSortOrder,
                in: context,
                now: placement.updatedAt,
            )
            context.delete(placement)
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private nonisolated static func loadLibraryItems(
        matching query: String? = nil,
        in context: NSManagedObjectContext,
    ) throws -> [LibraryItemListing] {
        let request = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(LibraryItemEntity.isPinned), ascending: false),
            NSSortDescriptor(key: #keyPath(LibraryItemEntity.updatedAt), ascending: false),
        ]
        if let query, !query.isEmpty {
            request.predicate = NSPredicate(format: "searchText CONTAINS[cd] %@", query)
        }

        return try context.fetch(request).compactMap(makeLibraryItemListing(from:))
    }

    private nonisolated static func loadLibraryItems(
        kind: LibraryItemKind,
        matching query: String? = nil,
        in context: NSManagedObjectContext,
    ) throws -> [LibraryItemEntity] {
        let request = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(LibraryItemEntity.isPinned), ascending: false),
            NSSortDescriptor(key: #keyPath(LibraryItemEntity.updatedAt), ascending: false),
        ]
        var predicates = [NSPredicate(format: "kind == %@", kind.rawValue)]
        if let query, !query.isEmpty {
            predicates.append(NSPredicate(format: "searchText CONTAINS[cd] %@", query))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try context.fetch(request)
    }

    private nonisolated static func loadLibraryItems(
        kind: LibraryItemKind,
        workspaceID: UUID,
        in context: NSManagedObjectContext,
    ) throws -> [LibraryItemEntity] {
        let request = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "kind == %@", kind.rawValue),
                NSPredicate(format: "workspaceID == %@", workspaceID as CVarArg),
            ],
        )
        return try context.fetch(request)
    }

    private nonisolated static func loadLibraryItems(
        kind: LibraryItemKind,
        windowID: UUID,
        in context: NSManagedObjectContext,
    ) throws -> [LibraryItemEntity] {
        let request = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "kind == %@", kind.rawValue),
                NSPredicate(format: "windowID == %@", windowID as CVarArg),
            ],
        )
        return try context.fetch(request)
    }

    private nonisolated static func loadLibraryItem(
        id: UUID,
        in context: NSManagedObjectContext,
    ) throws -> LibraryItemEntity? {
        let request = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private nonisolated static func loadLibraryItem(
        kind: LibraryItemKind,
        workspaceID: UUID,
        in context: NSManagedObjectContext,
    ) throws -> LibraryItemEntity? {
        try loadLibraryItems(kind: kind, workspaceID: workspaceID, in: context).first
    }

    private nonisolated static func loadLibraryItem(
        kind: LibraryItemKind,
        windowID: UUID,
        in context: NSManagedObjectContext,
    ) throws -> LibraryItemEntity? {
        try loadLibraryItems(kind: kind, windowID: windowID, in: context).first
    }

    private nonisolated static func requireOrCreateLibraryItem(
        kind: LibraryItemKind,
        workspaceID: UUID,
        context: NSManagedObjectContext,
    ) throws -> LibraryItemEntity {
        if let libraryItem = try loadLibraryItem(kind: kind, workspaceID: workspaceID, in: context) {
            return libraryItem
        }

        let entity = LibraryItemEntity(context: context)
        entity.id = UUID()
        entity.kind = kind.rawValue
        entity.workspaceID = workspaceID
        return entity
    }

    private nonisolated static func requireOrCreateLibraryItem(
        kind: LibraryItemKind,
        windowID: UUID,
        context: NSManagedObjectContext,
    ) throws -> LibraryItemEntity {
        if let libraryItem = try loadLibraryItem(kind: kind, windowID: windowID, in: context) {
            return libraryItem
        }

        let entity = LibraryItemEntity(context: context)
        entity.id = UUID()
        entity.kind = kind.rawValue
        entity.windowID = windowID
        return entity
    }

    private nonisolated static func isWorkspaceLive(workspaceID: UUID, in context: NSManagedObjectContext) -> Bool {
        let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "role == %@", WorkspacePlacementRole.live.rawValue),
                NSPredicate(format: "workspace.id == %@", workspaceID as CVarArg),
            ],
        )

        do {
            return try !context.fetch(request).isEmpty
        } catch {
            Logger.persistence.error("Core Data failed to determine whether a workspace is currently live while listing library items. The app will continue, but the library may briefly show a stale row. Workspace ID: \(workspaceID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private nonisolated static func isWindowOpen(windowID: UUID, in context: NSManagedObjectContext) -> Bool {
        do {
            return try loadWindowEntity(id: windowID, in: context)?.isOpen ?? false
        } catch {
            Logger.persistence.error("Core Data failed to determine whether a window is currently live while listing library items. The app will continue, but the library may briefly show a stale row. Window ID: \(windowID.uuidString, privacy: .public). Error: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private nonisolated static func migrateLegacyLibraryItems(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
        request.predicate = NSPredicate(format: "role == %@", WorkspacePersistenceLegacy.libraryPlacementRoleRawValue)
        let legacyPlacements = try context.fetch(request)
        guard !legacyPlacements.isEmpty else {
            return
        }

        for placement in legacyPlacements {
            guard let workspaceEntity = placement.workspace else {
                context.delete(placement)
                continue
            }

            let libraryItem = try requireOrCreateLibraryItem(
                kind: .workspace,
                workspaceID: workspaceEntity.id,
                context: context,
            )
            if libraryItem.objectID.isTemporaryID {
                libraryItem.createdAt = placement.createdAt
            }
            libraryItem.kind = LibraryItemKind.workspace.rawValue
            libraryItem.workspaceID = workspaceEntity.id
            libraryItem.windowID = nil
            libraryItem.updatedAt = placement.updatedAt
            libraryItem.lastOpenedAt = placement.lastOpenedAt
            libraryItem.isPinned = placement.isPinned
            libraryItem.title = placement.title
            libraryItem.previewText = placement.previewText
            libraryItem.searchText = placement.searchText
            libraryItem.paneCount = placement.paneCount
            libraryItem.workspaceCount = 1
            context.delete(placement)
        }

        if context.hasChanges {
            try context.save()
        }
    }

    @discardableResult
    private nonisolated static func upsertWindowLibraryItem(
        for sceneIdentity: WorkspaceSceneIdentity,
        in context: NSManagedObjectContext,
        now: Date,
    ) throws -> LibraryItemEntity? {
        guard let windowEntity = try loadWindowEntity(id: sceneIdentity.windowID, in: context) else {
            return nil
        }

        let livePlacements = loadPlacements(role: .live, sceneIdentity: sceneIdentity, in: context)
        guard !livePlacements.isEmpty else {
            return nil
        }

        let libraryItem = try requireOrCreateLibraryItem(
            kind: .window,
            windowID: sceneIdentity.windowID,
            context: context,
        )
        if libraryItem.objectID.isTemporaryID {
            libraryItem.createdAt = windowEntity.createdAt
        }
        libraryItem.kind = LibraryItemKind.window.rawValue
        libraryItem.workspaceID = nil
        libraryItem.windowID = sceneIdentity.windowID
        libraryItem.updatedAt = now
        refreshListingMetadata(on: libraryItem, from: windowEntity, livePlacements: livePlacements)
        return libraryItem
    }

    private nonisolated static func loadWindowWorkspaceMemberships(
        windowID: UUID,
        in context: NSManagedObjectContext,
    ) throws -> [WindowWorkspaceMembershipEntity] {
        let request = NSFetchRequest<WindowWorkspaceMembershipEntity>(entityName: "WindowWorkspaceMembershipEntity")
        request.predicate = NSPredicate(format: "windowID == %@", windowID as CVarArg)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(WindowWorkspaceMembershipEntity.sortOrder), ascending: true),
            NSSortDescriptor(key: #keyPath(WindowWorkspaceMembershipEntity.updatedAt), ascending: false),
        ]
        return try context.fetch(request)
    }

    private nonisolated static func loadWindowWorkspaceMemberships(
        workspaceID: UUID,
        in context: NSManagedObjectContext,
    ) throws -> [WindowWorkspaceMembershipEntity] {
        let request = NSFetchRequest<WindowWorkspaceMembershipEntity>(entityName: "WindowWorkspaceMembershipEntity")
        request.predicate = NSPredicate(format: "workspaceID == %@", workspaceID as CVarArg)
        return try context.fetch(request)
    }

    private nonisolated static func upsertWindowWorkspaceMembership(
        windowID: UUID,
        workspaceID: UUID,
        sortOrder: Int64,
        in context: NSManagedObjectContext,
        now: Date,
    ) throws {
        let request = NSFetchRequest<WindowWorkspaceMembershipEntity>(entityName: "WindowWorkspaceMembershipEntity")
        request.fetchLimit = 1
        request.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                NSPredicate(format: "windowID == %@", windowID as CVarArg),
                NSPredicate(format: "workspaceID == %@", workspaceID as CVarArg),
            ],
        )
        let membership = try context.fetch(request).first ?? WindowWorkspaceMembershipEntity(context: context)
        if membership.objectID.isTemporaryID {
            membership.id = UUID()
            membership.windowID = windowID
            membership.workspaceID = workspaceID
            membership.createdAt = now
        }
        membership.sortOrder = sortOrder
        membership.updatedAt = now
    }

    private nonisolated static func loadWindowEntities(
        matching windowIDs: [UUID]?,
        isOpen: Bool,
        in context: NSManagedObjectContext,
    ) throws -> [WorkspaceWindowEntity] {
        let request = NSFetchRequest<WorkspaceWindowEntity>(entityName: "WorkspaceWindowEntity")
        var predicates = [NSPredicate(format: "isOpen == %@", NSNumber(value: isOpen))]
        if let windowIDs, !windowIDs.isEmpty {
            predicates.append(NSPredicate(format: "id IN %@", windowIDs))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(key: #keyPath(WorkspaceWindowEntity.lastActiveAt), ascending: false),
            NSSortDescriptor(key: #keyPath(WorkspaceWindowEntity.updatedAt), ascending: false),
        ]
        return try context.fetch(request)
    }

    private nonisolated static func loadWindowEntity(
        id: UUID,
        in context: NSManagedObjectContext,
    ) throws -> WorkspaceWindowEntity? {
        let request = NSFetchRequest<WorkspaceWindowEntity>(entityName: "WorkspaceWindowEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private nonisolated static func requireOrCreateWindowEntity(
        id: UUID,
        context: NSManagedObjectContext,
    ) throws -> WorkspaceWindowEntity {
        if let entity = try loadWindowEntity(id: id, in: context) {
            return entity
        }

        let entity = WorkspaceWindowEntity(context: context)
        entity.id = id
        return entity
    }

    private nonisolated static func migrateAllLegacyWindowState(in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<WorkspaceWindowStateEntity>(entityName: "WorkspaceWindowStateEntity")
        let legacyWindows = try context.fetch(request)
        guard !legacyWindows.isEmpty else {
            return
        }

        for legacyWindow in legacyWindows {
            try migrateLegacyWindowState(
                for: WorkspaceSceneIdentity(windowID: legacyWindow.windowID),
                in: context,
            )
        }
    }

    private nonisolated static func migrateLegacyWindowStateIfNeeded(
        preferredSceneIdentities: [WorkspaceSceneIdentity],
        in context: NSManagedObjectContext,
    ) throws {
        for sceneIdentity in preferredSceneIdentities {
            try migrateLegacyWindowState(for: sceneIdentity, in: context)
            guard let window = try loadWindowEntity(id: sceneIdentity.windowID, in: context) else {
                continue
            }

            window.isOpen = true
        }

        if context.hasChanges {
            try context.save()
        }
    }

    private nonisolated static func migrateLegacyWindowState(
        for sceneIdentity: WorkspaceSceneIdentity,
        in context: NSManagedObjectContext,
    ) throws {
        let legacyRequest = NSFetchRequest<WorkspaceWindowStateEntity>(entityName: "WorkspaceWindowStateEntity")
        legacyRequest.fetchLimit = 1
        legacyRequest.predicate = NSPredicate(format: "windowID == %@", sceneIdentity.windowID as CVarArg)

        let livePlacements = loadPlacements(role: .live, sceneIdentity: sceneIdentity, in: context)
        let legacyWindowState = try context.fetch(legacyRequest).first

        guard legacyWindowState != nil || !livePlacements.isEmpty else {
            return
        }

        let now = Date()
        let window = try requireOrCreateWindowEntity(id: sceneIdentity.windowID, context: context)
        if window.objectID.isTemporaryID {
            window.id = sceneIdentity.windowID
            window.createdAt = legacyWindowState?.createdAt ?? livePlacements.first?.createdAt ?? now
        }
        window.updatedAt = legacyWindowState?.updatedAt ?? livePlacements.first?.updatedAt ?? now
        window.lastActiveAt = livePlacements.first?.updatedAt ?? legacyWindowState?.updatedAt ?? now
        if let selectedWorkspaceID = legacyWindowState?.selectedWorkspaceID {
            window.selectedWorkspaceID = selectedWorkspaceID
        }
        if let selectedPaneID = legacyWindowState?.selectedPaneID {
            window.selectedPaneID = selectedPaneID
        }
        if window.title == nil {
            window.title = livePlacements.first?.title
        }
        if !livePlacements.isEmpty {
            window.isOpen = true
        }

        if let legacyWindowState {
            context.delete(legacyWindowState)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    private nonisolated static func retainedWorkspaceIDs(in context: NSManagedObjectContext) throws -> Set<UUID> {
        let placementRequest = NSFetchRequest<WorkspacePlacementEntity>(entityName: "WorkspacePlacementEntity")
        let libraryItemRequest = NSFetchRequest<LibraryItemEntity>(entityName: "LibraryItemEntity")
        let membershipRequest = NSFetchRequest<WindowWorkspaceMembershipEntity>(entityName: "WindowWorkspaceMembershipEntity")
        let placementWorkspaceIDs: [UUID] = try context.fetch(placementRequest).compactMap { placement in
            guard !placement.isDeleted else {
                return nil
            }

            return placement.workspace?.id
        }
        let libraryWorkspaceIDs: [UUID] = try context.fetch(libraryItemRequest).compactMap { libraryItem in
            guard !libraryItem.isDeleted else {
                return nil
            }

            return libraryItem.workspaceID
        }
        let membershipWorkspaceIDs: [UUID] = try context.fetch(membershipRequest).compactMap { membership in
            guard !membership.isDeleted else {
                return nil
            }

            return membership.workspaceID
        }
        return Set(placementWorkspaceIDs + libraryWorkspaceIDs + membershipWorkspaceIDs)
    }

    private nonisolated static func loadWorkspaceEntity(id: UUID, in context: NSManagedObjectContext) throws -> WorkspaceEntity? {
        let request = NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    private nonisolated static func requireWorkspaceEntity(id: UUID, context: NSManagedObjectContext) throws -> WorkspaceEntity {
        guard let entity = try loadWorkspaceEntity(id: id, in: context) else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }

        return entity
    }

    private nonisolated static func requireOrCreateWorkspaceEntity(
        id: UUID,
        context: NSManagedObjectContext,
    ) throws -> WorkspaceEntity {
        if let entity = try loadWorkspaceEntity(id: id, in: context) {
            return entity
        }

        let entity = WorkspaceEntity(context: context)
        entity.id = id
        return entity
    }

    private nonisolated static func makePreviewText(from transcript: String) -> String? {
        transcript
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(160)) }
    }
}
