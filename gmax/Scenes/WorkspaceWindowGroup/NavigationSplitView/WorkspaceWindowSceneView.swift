import AppKit
import OSLog
import SwiftUI

private enum WorkspaceWindowSceneStorageKey {
    static let selectedWorkspaceID = "workspaceWindow.selectedWorkspaceID"
    static let isInspectorVisible = "workspaceWindow.isInspectorVisible"
    static let isSidebarVisible = "workspaceWindow.isSidebarVisible"
}

private enum FocusAssignment: Equatable {
    case none
    case inspector
    case pane(PaneID)
}

struct WorkspaceWindowSceneView: View {
    @AppStorage(WorkspacePersistenceDefaults.autoSaveClosedItemsKey)
    private var autoSaveClosedItems = false
    @AppStorage(WorkspacePersistenceDefaults.backgroundSaveIntervalMinutesKey)
    private var backgroundSaveIntervalMinutes = WorkspacePersistenceDefaults.defaultBackgroundSaveIntervalMinutes
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.dismiss) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focusedTarget: WorkspaceFocusTarget?
    @SceneStorage(WorkspaceWindowSceneStorageKey.selectedWorkspaceID) private var restoredSelectedWorkspaceID: String?
    @SceneStorage(WorkspaceWindowSceneStorageKey.isInspectorVisible) private var restoredInspectorVisible = true
    @SceneStorage(WorkspaceWindowSceneStorageKey.isSidebarVisible) private var restoredSidebarVisible = true
    @State private var selectedWorkspaceID: WorkspaceID?
    @State private var workspacePendingDeletionID: WorkspaceID?
    @State private var workspacePendingRenameID: WorkspaceID?
    @State private var workspaceRenameTitleDraft = ""
    @State private var isLibraryPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorVisible = true
    @State private var hasAppliedSceneState = false
    @State private var paneFrames: [PaneID: CGRect] = [:]
    @State private var paneFocusHistory: [PaneID] = []
    @State private var browserOmniboxRevealIDByPaneID: [PaneID: Int] = [:]
    @State private var pendingFocusedPaneID: PaneID?
    @State private var pendingWorkspaceSelectionFocusPaneID: PaneID?
    @State private var pendingHistoryPaneID: PaneID?
    @State private var shouldSaveWindowToLibraryOnClose = false
    @StateObject private var workspaceStore: WorkspaceStore

    private let sceneIdentity: WorkspaceSceneIdentity
    private let windowRestoration: WorkspaceWindowRestorationController

    init(
        sceneIdentity: WorkspaceSceneIdentity = WorkspaceSceneIdentity(),
        windowRestoration: WorkspaceWindowRestorationController,
    ) {
        self.sceneIdentity = sceneIdentity
        self.windowRestoration = windowRestoration
        _workspaceStore = StateObject(
            wrappedValue: WorkspaceStore(sceneIdentity: sceneIdentity),
        )
    }

    var body: some View {
        let openLibrary = {
            isLibraryPresented = true
        }
        let isSidebarVisible = columnVisibility == .all
        let toggleSidebar = {
            let sidebarWillBeVisible = columnVisibility != .all
            columnVisibility = sidebarWillBeVisible ? .all : .detailOnly
            Logger.diagnostics.notice(
                "Toggled sidebar visibility in the active shell window. Sidebar is now \(sidebarWillBeVisible ? "visible" : "hidden", privacy: .public).",
            )
        }
        let toggleInspector = {
            isInspectorVisible.toggle()
            Logger.diagnostics.notice(
                "Toggled inspector visibility in the active shell window. Inspector is now \(isInspectorVisible ? "visible" : "hidden", privacy: .public).",
            )
        }
        let closeWindow = {
            shouldSaveWindowToLibraryOnClose = false
            dismissWindow()
        }
        let closeWindowToLibrary = {
            shouldSaveWindowToLibraryOnClose = true
            dismissWindow()
        }
        let pruneBrowserOmniboxState = {
            let activePaneIDs = Set(
                workspaceStore.workspaces.flatMap { workspace in
                    workspace.paneLeaves.map(\.id)
                },
            )
            browserOmniboxRevealIDByPaneID = browserOmniboxRevealIDByPaneID.filter { activePaneIDs.contains($0.key) }
        }
        let normalizeSelection = {
            selectedWorkspaceID = if let selectedWorkspaceID, workspaceStore.workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
                selectedWorkspaceID
            } else {
                workspaceStore.workspaces.first?.id
            }
        }
        let dismissWorkspaceDeletion = {
            if let workspacePendingDeletionID {
                Logger.diagnostics.notice(
                    "Dismissed workspace deletion confirmation without deleting the workspace. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)",
                )
            }
            workspacePendingDeletionID = nil
        }
        let dismissWorkspaceRename = {
            if let workspacePendingRenameID {
                Logger.diagnostics.notice(
                    "Dismissed the workspace rename sheet without saving changes. Workspace ID: \(workspacePendingRenameID.rawValue.uuidString, privacy: .public)",
                )
            }
            workspacePendingRenameID = nil
        }
        let presentWorkspaceRename: (WorkspaceID) -> Void = { workspaceID in
            guard let workspace = workspaceStore.workspaces.first(where: { $0.id == workspaceID }) else {
                Logger.diagnostics.notice(
                    "Skipped presenting the workspace rename sheet because the requested workspace no longer exists in the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)",
                )
                return
            }

            workspaceRenameTitleDraft = workspace.title
            workspacePendingRenameID = workspace.id
            selectedWorkspaceID = workspace.id
            Logger.diagnostics.notice(
                "Presented the workspace rename sheet for the active shell window. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)",
            )
        }
        let presentWorkspaceDeletion: (WorkspaceID) -> Void = { workspaceID in
            guard workspaceStore.workspaces.count > 1, workspaceStore.workspaces.contains(where: { $0.id == workspaceID }) else {
                Logger.diagnostics.notice(
                    "Skipped presenting workspace deletion confirmation because the selected workspace cannot be deleted safely. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)",
                )
                return
            }

            workspacePendingDeletionID = workspaceID
            Logger.diagnostics.notice(
                "Presented workspace deletion confirmation for the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)",
            )
        }
        let pendingDeletionWorkspace = workspacePendingDeletionID.flatMap { workspaceID in workspaceStore.workspaces.first { $0.id == workspaceID } }
        let pendingRenameWorkspace = workspacePendingRenameID.flatMap { workspaceID in workspaceStore.workspaces.first { $0.id == workspaceID } }
        let dismissPresentedWorkspaceModal: (() -> Void)? = {
            if isLibraryPresented {
                return {
                    Logger.diagnostics.notice(
                        "Dismissed the library sheet from the active shell window without reopening a workspace or window.",
                    )
                    isLibraryPresented = false
                }
            }
            if pendingRenameWorkspace != nil {
                return dismissWorkspaceRename
            }
            if pendingDeletionWorkspace != nil {
                return dismissWorkspaceDeletion
            }
            return nil
        }()
        let hasPresentedWorkspaceModal = dismissPresentedWorkspaceModal != nil
        let normalizedBackgroundSaveIntervalMinutes = WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(
            backgroundSaveIntervalMinutes,
        )
        let selectedWorkspace = selectedWorkspaceID.flatMap { selectedWorkspaceID in
            workspaceStore.workspaces.first { $0.id == selectedWorkspaceID }
        }
        let focusedPaneID: PaneID? = {
            if case let .pane(paneID) = focusedTarget {
                return paneID
            }
            return nil
        }()
        let activePaneIDs = Set(selectedWorkspace?.paneLeaves.map(\.id) ?? [])
        let paneIDsInWorkspace: (WorkspaceID) -> Set<PaneID> = { workspaceID in
            Set(
                workspaceStore.workspaces
                    .first(where: { $0.id == workspaceID })?
                    .paneLeaves
                    .map(\.id) ?? [],
            )
        }
        let currentActivePaneIDs = {
            selectedWorkspaceID.map(paneIDsInWorkspace) ?? []
        }
        let inspectedPaneID: PaneID? = {
            if case let .pane(paneID) = focusedTarget, activePaneIDs.contains(paneID) {
                return paneID
            }

            return paneFocusHistory.last(where: { activePaneIDs.contains($0) })
        }()
        let prunePaneNavigationState = {
            let activePaneIDs = currentActivePaneIDs()
            paneFrames = paneFrames.filter { activePaneIDs.contains($0.key) }
            paneFocusHistory = paneFocusHistory.filter { activePaneIDs.contains($0) }
            pendingHistoryPaneID = pendingHistoryPaneID.flatMap { activePaneIDs.contains($0) ? $0 : nil }
        }
        let applyFocusAssignment: (FocusAssignment) -> Void = { assignment in
            let activePaneIDs = currentActivePaneIDs()
            let normalizedAssignment: FocusAssignment = switch assignment {
                case let .pane(paneID) where activePaneIDs.contains(paneID):
                    .pane(paneID)
                case .pane:
                    .none
                case .inspector:
                    .inspector
                case .none:
                    .none
            }

            focusedTarget = switch normalizedAssignment {
                case let .pane(paneID):
                    .pane(paneID)
                case .inspector:
                    .inspector
                case .none:
                    nil
            }
        }
        let focusPaneTarget: (PaneID?) -> Void = { paneID in
            applyFocusAssignment(paneID.map(FocusAssignment.pane) ?? .none)
        }
        let recordFocusedPaneInHistory: (PaneID) -> Void = { paneID in
            pendingHistoryPaneID = paneID
            Task { @MainActor in
                await Task.yield()
                guard pendingHistoryPaneID == paneID else {
                    return
                }

                paneFocusHistory.removeAll { $0 == paneID }
                paneFocusHistory.append(paneID)
                pendingHistoryPaneID = nil
            }
        }
        let requestPaneFocus: (PaneID?) -> Void = { paneID in
            guard let paneID else {
                pendingFocusedPaneID = nil
                applyFocusAssignment(.none)
                return
            }

            pendingFocusedPaneID = paneID
            Task { @MainActor in
                await Task.yield()
                guard pendingFocusedPaneID == paneID else {
                    return
                }

                focusPaneTarget(paneID)
                pendingFocusedPaneID = nil
            }
        }
        let firstPaneIDInWorkspace: (WorkspaceID?) -> PaneID? = { workspaceID in
            guard let workspaceID else {
                return nil
            }

            return workspaceStore.workspaces
                .first(where: { $0.id == workspaceID })?
                .root?
                .firstLeaf()?
                .id
        }
        let selectWorkspaceAndRepairFocus: (WorkspaceID?) -> Void = { workspaceID in
            selectedWorkspaceID = workspaceID
            pendingWorkspaceSelectionFocusPaneID = firstPaneIDInWorkspace(workspaceID)
            prunePaneNavigationState()
            pruneBrowserOmniboxState()
        }
        let createWorkspaceAndFocus: () -> Void = {
            let workspaceID = workspaceStore.createWorkspace()
            selectWorkspaceAndRepairFocus(workspaceID)
        }
        let duplicateWorkspaceAndFocus: (WorkspaceID) -> Void = { workspaceID in
            let duplicatedWorkspaceID = workspaceStore.duplicateWorkspace(workspaceID)
            selectWorkspaceAndRepairFocus(duplicatedWorkspaceID)
        }
        let closeSelectedWorkspaceAndFocus: () -> Void = {
            guard let selectedWorkspaceID else {
                Logger.diagnostics.notice(
                    "Skipped the close-workspace command because the active shell scene has no selected workspace.",
                )
                return
            }

            let nextWorkspaceID = workspaceStore.closeWorkspace(selectedWorkspaceID)
            selectWorkspaceAndRepairFocus(nextWorkspaceID)
        }
        let closeWorkspaceToLibraryAndFocus: (WorkspaceID) -> Void = { workspaceID in
            let nextWorkspaceID = workspaceStore.closeWorkspaceToLibrary(workspaceID)
            selectWorkspaceAndRepairFocus(nextWorkspaceID)
        }
        let closeWorkspaceAndFocus: (WorkspaceID) -> Void = { workspaceID in
            let nextWorkspaceID = workspaceStore.closeWorkspace(workspaceID)
            selectWorkspaceAndRepairFocus(nextWorkspaceID)
        }
        let createPaneInWorkspace: (WorkspaceID) -> Void = { workspaceID in
            let createdPaneID = workspaceStore.createPane(in: workspaceID)
            prunePaneNavigationState()
            pruneBrowserOmniboxState()
            requestPaneFocus(createdPaneID)
        }
        let splitPaneInWorkspace: (WorkspaceID, PaneID, SplitDirection) -> Void = { workspaceID, paneID, direction in
            let insertedPaneID = workspaceStore.splitPane(paneID, in: workspaceID, direction: direction)
            prunePaneNavigationState()
            pruneBrowserOmniboxState()
            requestPaneFocus(insertedPaneID)
        }
        let closePaneInWorkspace: (WorkspaceID, PaneID) -> Void = { workspaceID, paneID in
            workspaceStore.closePane(paneID, in: workspaceID)
            prunePaneNavigationState()
            pruneBrowserOmniboxState()
            switch paneFocusTargetAfterClosingPane(
                closedPaneID: paneID,
                focusedTarget: focusedTarget,
                survivingPaneIDs: paneIDsInWorkspace(workspaceID),
                paneFocusHistory: paneFocusHistory,
                isInspectorVisible: isInspectorVisible,
            ) {
                case let .pane(paneID):
                    requestPaneFocus(paneID)
                case .inspector:
                    applyFocusAssignment(.inspector)
                case .sidebar, nil:
                    applyFocusAssignment(.none)
            }
        }
        let moveFocusedPaneFocus: (PaneFocusDirection) -> Void = { direction in
            guard let selectedWorkspace else {
                return
            }

            let paneLeaves = selectedWorkspace.paneLeaves
            guard !paneLeaves.isEmpty else {
                applyFocusAssignment(.none)
                return
            }
            guard
                let currentFocusedPaneID = focusedPaneID,
                let focusedIndex = paneLeaves.firstIndex(where: { $0.id == currentFocusedPaneID })
            else {
                let fallbackPaneID = switch direction {
                    case .previous:
                        paneLeaves.last?.id
                    default:
                        paneLeaves.first?.id
                }
                focusPaneTarget(fallbackPaneID)
                return
            }

            let nextPaneID: PaneID? = switch direction {
                case .next:
                    paneLeaves[(focusedIndex + 1) % paneLeaves.count].id
                case .previous:
                    paneLeaves[(focusedIndex - 1 + paneLeaves.count) % paneLeaves.count].id
                case .left, .right, .up, .down:
                    directionalPaneFocus(
                        from: currentFocusedPaneID,
                        paneFrames: paneFrames,
                        direction: direction,
                        history: paneFocusHistory,
                    )
            }

            focusPaneTarget(nextPaneID ?? currentFocusedPaneID)
        }
        let splitFocusedPane: (SplitDirection) -> Void = { direction in
            guard let selectedWorkspaceID, let focusedPaneID else {
                return
            }

            let insertedPaneID = workspaceStore.splitPane(focusedPaneID, in: selectedWorkspaceID, direction: direction)
            prunePaneNavigationState()
            pruneBrowserOmniboxState()
            requestPaneFocus(insertedPaneID)
        }
        let splitFocusedPaneAsBrowser: (SplitDirection) -> Void = { direction in
            guard let selectedWorkspaceID, let focusedPaneID else {
                return
            }

            let insertedPaneID = workspaceStore.splitBrowserPane(focusedPaneID, in: selectedWorkspaceID, direction: direction)
            prunePaneNavigationState()
            pruneBrowserOmniboxState()
            requestPaneFocus(insertedPaneID)
        }
        let canSplitFocusedPane = selectedWorkspace.flatMap { workspace in
            focusedPaneID.flatMap { workspace.root?.findPane(id: $0) }
        } != nil
        let startShellInSelectedWorkspaceAction: (() -> Void)? = if let selectedWorkspaceID,
                                                                   selectedWorkspace?.root == nil {
            {
                createPaneInWorkspace(selectedWorkspaceID)
            }
        } else {
            nil
        }
        let focusedBrowserPane: PaneLeaf? = {
            guard let selectedWorkspace, let focusedPaneID else {
                return nil
            }
            guard let pane = selectedWorkspace.root?.findPane(id: focusedPaneID) else {
                return nil
            }
            guard pane.browserSessionID != nil else {
                return nil
            }

            return pane
        }()
        let focusedBrowserSession: BrowserSession? = focusedBrowserPane
            .flatMap(\.browserSessionID)
            .flatMap { browserSessionsID in
                workspaceStore.browserSessions.session(for: browserSessionsID)
            }
        let focusedBrowserController: BrowserPaneController? = {
            guard let focusedBrowserPane, let focusedBrowserSession else {
                return nil
            }

            return workspaceStore.browserPaneControllers.controller(
                for: focusedBrowserPane,
                session: focusedBrowserSession,
            )
        }()
        let moveFocusedPaneFocusAction = focusedPaneID == nil ? nil : moveFocusedPaneFocus
        let splitFocusedPaneAction: ((SplitDirection) -> Void)? = canSplitFocusedPane ? splitFocusedPane : nil
        let splitFocusedPaneAsBrowserAction: ((SplitDirection) -> Void)? = canSplitFocusedPane ? splitFocusedPaneAsBrowser : nil
        let goBackFocusedBrowserPaneAction: (() -> Void)? = if focusedBrowserSession?.canGoBack == true,
                                                               let focusedBrowserController {
            {
                focusedBrowserController.goBack()
            }
        } else {
            nil
        }
        let goForwardFocusedBrowserPaneAction: (() -> Void)? = if focusedBrowserSession?.canGoForward == true,
                                                                  let focusedBrowserController {
            {
                focusedBrowserController.goForward()
            }
        } else {
            nil
        }
        let reloadFocusedBrowserPaneAction: (() -> Void)? = if let focusedBrowserController {
            {
                focusedBrowserController.reload()
            }
        } else {
            nil
        }
        let focusFocusedBrowserOmniboxAction: (() -> Void)? = if let focusedBrowserPane {
            {
                browserOmniboxRevealIDByPaneID[focusedBrowserPane.id] =
                    (browserOmniboxRevealIDByPaneID[focusedBrowserPane.id] ?? 0) + 1
            }
        } else {
            nil
        }
        let closeFocusedPaneAction: (() -> Void)? = {
            guard let selectedWorkspaceID, let focusedPaneID else {
                return nil
            }

            return {
                closePaneInWorkspace(selectedWorkspaceID, focusedPaneID)
            }
        }()

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarPane(
                model: workspaceStore,
                selection: $selectedWorkspaceID,
                focusedTarget: $focusedTarget,
                openLibrary: openLibrary,
                createWorkspace: createWorkspaceAndFocus,
                duplicateWorkspace: duplicateWorkspaceAndFocus,
                closeWorkspaceToLibrary: closeWorkspaceToLibraryAndFocus,
                closeWorkspace: closeWorkspaceAndFocus,
                requestRenameWorkspace: presentWorkspaceRename,
                requestDeleteWorkspace: presentWorkspaceDeletion,
            )
            .navigationSplitViewColumnWidth(ideal: 220)
        } detail: {
            ContentPane(
                model: workspaceStore,
                selectedWorkspaceID: $selectedWorkspaceID,
                focusedTarget: $focusedTarget,
                onCreatePane: createPaneInWorkspace,
                onSplitPane: splitPaneInWorkspace,
                onClosePane: closePaneInWorkspace,
                onUpdatePaneFrames: { paneFrames in
                    self.paneFrames = paneFrames
                    prunePaneNavigationState()
                },
                onMovePaneFocus: moveFocusedPaneFocus,
                browserOmniboxRevealIDByPaneID: browserOmniboxRevealIDByPaneID,
            )
            .navigationSplitViewColumnWidth(ideal: 760)
        }
        .inspector(isPresented: $isInspectorVisible) {
            DetailPane(
                model: workspaceStore,
                selectedWorkspaceID: $selectedWorkspaceID,
                inspectedPaneID: inspectedPaneID,
                focusedTarget: $focusedTarget,
            )
            .inspectorColumnWidth(ideal: 260)
        }
        .modifier(WorkspaceWindowPresentationModifier(
            workspaceStore: workspaceStore,
            selectedWorkspaceID: $selectedWorkspaceID,
            isLibraryPresented: $isLibraryPresented,
            deleteAlertIsPresented: Binding(
                get: { workspacePendingDeletionID != nil },
                set: { isPresented in
                    if !isPresented {
                        dismissWorkspaceDeletion()
                    }
                },
            ),
            deleteWorkspaceTitle: pendingDeletionWorkspace?.title,
            confirmDelete: {
                confirmWorkspaceDeletion(normalizeSelection: normalizeSelection)
            },
            cancelDelete: dismissWorkspaceDeletion,
            renameSheetIsPresented: Binding(
                get: { pendingRenameWorkspace != nil },
                set: { isPresented in
                    if !isPresented {
                        dismissWorkspaceRename()
                    }
                },
            ),
            workspaceRenameTitleDraft: $workspaceRenameTitleDraft,
            cancelRename: dismissWorkspaceRename,
            saveRename: saveWorkspaceRename,
        ))
        .focusedSceneObject(workspaceStore)
        .focusedSceneValue(\.activeWorkspaceFocusTarget, focusedTarget)
        .focusedSceneValue(\.activeWorkspaceSceneIdentity, sceneIdentity)
        .focusedSceneValue(\.selectedWorkspaceSelection, $selectedWorkspaceID)
        .focusedSceneValue(\.createWorkspaceAndFocus, createWorkspaceAndFocus)
        .focusedSceneValue(\.closeSelectedWorkspaceAndFocus, closeSelectedWorkspaceAndFocus)
        .focusedSceneValue(\.dismissPresentedWorkspaceModal, dismissPresentedWorkspaceModal)
        .focusedSceneValue(\.isWorkspaceSidebarVisible, isSidebarVisible)
        .focusedSceneValue(\.toggleWorkspaceSidebar, toggleSidebar)
        .focusedSceneValue(\.isWorkspaceInspectorVisible, isInspectorVisible)
        .focusedSceneValue(\.toggleWorkspaceInspector, toggleInspector)
        .focusedSceneValue(\.closeWorkspaceWindow, closeWindow)
        .focusedSceneValue(\.closeWorkspaceWindowToLibrary, closeWindowToLibrary)
        .focusedSceneValue(\.openLibrary, openLibrary)
        .focusedSceneValue(\.presentWorkspaceRename, presentWorkspaceRename)
        .focusedSceneValue(\.presentWorkspaceDeletion, presentWorkspaceDeletion)
        .focusedSceneValue(\.moveFocusedPaneFocus, moveFocusedPaneFocusAction)
        .focusedSceneValue(\.startShellInSelectedWorkspace, startShellInSelectedWorkspaceAction)
        .focusedSceneValue(\.splitFocusedPane, splitFocusedPaneAction)
        .focusedSceneValue(\.splitFocusedPaneAsBrowser, splitFocusedPaneAsBrowserAction)
        .focusedSceneValue(\.goBackFocusedBrowserPane, goBackFocusedBrowserPaneAction)
        .focusedSceneValue(\.goForwardFocusedBrowserPane, goForwardFocusedBrowserPaneAction)
        .focusedSceneValue(\.reloadFocusedBrowserPane, reloadFocusedBrowserPaneAction)
        .focusedSceneValue(\.focusFocusedBrowserOmnibox, focusFocusedBrowserOmniboxAction)
        .focusedSceneValue(\.closeFocusedPane, closeFocusedPaneAction)
        .modifier(WorkspaceWindowLifecycleModifier(
            normalizedBackgroundSaveIntervalMinutes: normalizedBackgroundSaveIntervalMinutes,
            onInitialTask: {
                guard !hasAppliedSceneState else {
                    return
                }

                windowRestoration.markWindowOpen(sceneIdentity)
                applyInitialSceneRestoration(normalizeSelection: normalizeSelection)
                Task { @MainActor in
                    await Task.yield()
                    for sceneIdentity in windowRestoration.consumePendingLaunchRestoreSceneIdentities() {
                        openWindow(value: sceneIdentity)
                    }
                }
            },
            onBackgroundSaveTask: {
                await runPeriodicPersistenceLoop(
                    every: normalizedBackgroundSaveIntervalMinutes,
                    workspaceStore: workspaceStore,
                )
            },
            onWillTerminate: {
                windowRestoration.noteApplicationWillTerminate()
                workspaceStore.persistSceneStateNow(
                    reason: WorkspacePersistenceSaveReason.appWillTerminate,
                )
            },
            selectedWorkspaceIDString: selectedWorkspaceID?.rawValue.uuidString,
            onSelectedWorkspaceIDStringChange: { restoredSelectedWorkspaceID = $0 },
            focusedTarget: focusedTarget,
            onFocusedTargetChange: { newValue in
                handleFocusedTargetChange(
                    newValue,
                    activePaneIDs: activePaneIDs,
                    recordFocusedPaneInHistory: recordFocusedPaneInHistory,
                )
            },
            workspaceIDs: workspaceStore.workspaces.map(\.id.rawValue),
            onWorkspaceIDsChange: {
                normalizeSelection()
            },
            selectedWorkspaceID: selectedWorkspaceID,
            onSelectedWorkspaceChange: {
                resetPaneNavigationStateForWorkspaceSelection()
                handleSelectedWorkspacePersistence(selectedWorkspaceID)
            },
            selectedWorkspacePaneIDs: selectedWorkspace?.paneLeaves.map(\.id) ?? [],
            onSelectedWorkspacePaneChange: { paneIDs in
                handleSelectedWorkspacePaneChange(
                    paneIDs: paneIDs,
                    applyFocusAssignment: applyFocusAssignment,
                )
                if let pendingWorkspaceSelectionFocusPaneID,
                   paneIDs.contains(pendingWorkspaceSelectionFocusPaneID) {
                    restorePaneFocusAfterWindowActivationDirect(
                        pendingWorkspaceSelectionFocusPaneID,
                        activePaneIDs: Set(paneIDs),
                    )
                    self.pendingWorkspaceSelectionFocusPaneID = nil
                }
            },
            isInspectorVisible: isInspectorVisible,
            onInspectorVisibilityChange: { newValue in
                handleInspectorVisibilityChange(
                    newValue,
                    inspectedPaneID: inspectedPaneID,
                    focusPaneTarget: focusPaneTarget,
                )
            },
            columnVisibility: columnVisibility,
            onColumnVisibilityChange: { restoredSidebarVisible = $0 == .all },
            scenePhase: scenePhase,
            onScenePhaseChange: handleScenePhaseChange,
            appearsActive: appearsActive,
            onAppearsActiveChange: { newValue in
                workspaceStore.persistSceneStateNow(
                    reason: newValue
                        ? .windowBecameActive
                        : .windowResignedActive,
                )
                handleWindowAppearanceChange(
                    newValue,
                    activePaneIDs: activePaneIDs,
                    hasPresentedWorkspaceModal: hasPresentedWorkspaceModal,
                )
            },
            onDisappear: {
                workspaceStore.persistSceneStateNow(
                    reason: WorkspacePersistenceSaveReason.windowDisappeared,
                )
                windowRestoration.recordWindowClosed(
                    sceneIdentity,
                    saveToLibrary: shouldSaveWindowToLibraryOnClose || autoSaveClosedItems,
                )
                shouldSaveWindowToLibraryOnClose = false
            },
        ))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Split Right", systemImage: "uiwindow.split.2x1") {
                    splitFocusedPane(.right)
                }
                .labelStyle(.iconOnly)
                .help("Split the focused pane to the right (\u{2318}D)")
                .disabled(!canSplitFocusedPane)
                .accessibilityIdentifier("workspaceWindow.splitRightButton")

                Button("Split Down", systemImage: "uiwindow.split.2x1") {
                    splitFocusedPane(.down)
                }
                .labelStyle(.iconOnly)
                .help("Split the focused pane downward (\u{21E7}\u{2318}D)")
                .disabled(!canSplitFocusedPane)
                .accessibilityIdentifier("workspaceWindow.splitDownButton")
            }

            ToolbarItem(placement: .primaryAction) {
                Button(
                    isInspectorVisible ? "Hide Inspector" : "Show Inspector",
                    systemImage: "sidebar.right",
                ) {
                    toggleInspector()
                }
                .labelStyle(.iconOnly)
                .help(isInspectorVisible ? "Hide the inspector (\u{21E7}\u{2318}B)" : "Show the inspector (\u{21E7}\u{2318}B)")
                .accessibilityIdentifier("workspaceWindow.toggleInspectorButton")
            }
        }
    }

    private func runPeriodicPersistenceLoop(
        every intervalMinutes: Int,
        workspaceStore: WorkspaceStore,
    ) async {
        let intervalSeconds = intervalMinutes * 60
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(intervalSeconds))
            guard !Task.isCancelled else {
                break
            }

            workspaceStore.persistSceneStateNow(
                reason: WorkspacePersistenceSaveReason.backgroundIntervalElapsed,
            )
        }
    }

    private func applyInitialSceneRestoration(
        normalizeSelection: () -> Void,
    ) {
        hasAppliedSceneState = true

        let sceneStorageWorkspaceUUID = restoredSelectedWorkspaceID.flatMap(UUID.init(uuidString:))
        let sceneStorageSelection = sceneStorageWorkspaceUUID.map(WorkspaceID.init(rawValue:))
        let restoredSelection = workspaceStore.persistedSelectedWorkspaceID ?? sceneStorageSelection
        let fallbackWorkspaceID = workspaceStore.workspaces.first?.id

        if let restoredSelection {
            selectedWorkspaceID = restoredSelection
        } else {
            selectedWorkspaceID = fallbackWorkspaceID
        }

        normalizeSelection()
        columnVisibility = restoredSidebarVisible ? .all : .detailOnly
        isInspectorVisible = restoredInspectorVisible

        Logger.diagnostics.notice(
            """
            Applied per-window shell scene restoration. Durable selected workspace: \(workspaceStore.persistedSelectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public). \
            SceneStorage selected workspace: \(sceneStorageSelection?.rawValue.uuidString ?? "(none)", privacy: .public). \
            Restored workspace selection: \(restoredSelection?.rawValue.uuidString ?? "(none)", privacy: .public). \
            Normalized workspace selection: \(selectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public). \
            Sidebar visibility: \(restoredSidebarVisible ? "visible" : "hidden", privacy: .public). \
            Inspector visibility: \(restoredInspectorVisible ? "visible" : "hidden", privacy: .public).
            """,
        )
    }

    private func handleFocusedTargetChange(
        _ newValue: WorkspaceFocusTarget?,
        activePaneIDs: Set<PaneID>,
        recordFocusedPaneInHistory: (PaneID) -> Void,
    ) {
        guard let newValue else {
            pendingHistoryPaneID = nil
            return
        }
        guard case let .pane(paneID) = newValue else {
            pendingHistoryPaneID = nil
            return
        }

        let isActivePane = activePaneIDs.contains(paneID)
        guard isActivePane else {
            pendingHistoryPaneID = nil
            return
        }

        recordFocusedPaneInHistory(paneID)
    }

    private func handleWindowAppearanceChange(
        _ newValue: Bool,
        activePaneIDs: Set<PaneID>,
        hasPresentedWorkspaceModal: Bool,
    ) {
        guard newValue else {
            return
        }

        let restoredPaneFocusTarget = paneFocusTargetAfterActivatingWindow(
            focusedTarget: focusedTarget,
            survivingPaneIDs: activePaneIDs,
            paneFocusHistory: paneFocusHistory,
            isInspectorVisible: isInspectorVisible,
            hasPresentedWorkspaceModal: hasPresentedWorkspaceModal,
        )

        guard let restoredPaneFocusTarget else {
            return
        }

        if case let .pane(paneID) = restoredPaneFocusTarget {
            restorePaneFocusAfterWindowActivationDirect(
                paneID,
                activePaneIDs: activePaneIDs,
            )
            return
        }

        if restoredPaneFocusTarget == .inspector {
            applyFocusAssignmentDirect(
                .inspector,
                activePaneIDs: activePaneIDs,
            )
        }
    }

    private func handleSelectedWorkspacePersistence(_ selectedWorkspaceID: WorkspaceID?) {
        workspaceStore.persistedSelectedWorkspaceID = selectedWorkspaceID
        if selectedWorkspaceID == nil {
            pendingWorkspaceSelectionFocusPaneID = nil
        }
    }

    private func applyFocusAssignmentDirect(
        _ assignment: FocusAssignment,
        activePaneIDs: Set<PaneID>,
    ) {
        let normalizedAssignment: FocusAssignment = switch assignment {
            case let .pane(paneID) where activePaneIDs.contains(paneID):
                .pane(paneID)
            case .pane:
                .none
            case .inspector:
                .inspector
            case .none:
                .none
        }

        focusedTarget = switch normalizedAssignment {
            case let .pane(paneID):
                .pane(paneID)
            case .inspector:
                .inspector
            case .none:
                nil
        }
    }

    private func restorePaneFocusAfterWindowActivationDirect(
        _ paneID: PaneID,
        activePaneIDs: Set<PaneID>,
    ) {
        pendingFocusedPaneID = paneID
        Task { @MainActor in
            await Task.yield()
            guard pendingFocusedPaneID == paneID else {
                return
            }

            if focusedTarget == .pane(paneID) {
                applyFocusAssignmentDirect(.none, activePaneIDs: activePaneIDs)
                await Task.yield()
            }

            applyFocusAssignmentDirect(.pane(paneID), activePaneIDs: activePaneIDs)
            pendingFocusedPaneID = nil
        }
    }

    private func resetPaneNavigationStateForWorkspaceSelection() {
        paneFrames = [:]
        paneFocusHistory = []
        pendingFocusedPaneID = nil
        pendingHistoryPaneID = nil
    }

    private func handleSelectedWorkspacePaneChange(
        paneIDs: [PaneID],
        applyFocusAssignment: (FocusAssignment) -> Void,
    ) {
        let activePaneIDs = Set(paneIDs)
        let normalizedState = normalizedPaneNavigationState(activePaneIDs: activePaneIDs)
        paneFrames = normalizedState.paneFrames
        paneFocusHistory = normalizedState.paneFocusHistory
        pendingFocusedPaneID = normalizedState.pendingFocusedPaneID
        pendingHistoryPaneID = normalizedState.pendingHistoryPaneID

        if case let .pane(paneID) = focusedTarget, !activePaneIDs.contains(paneID) {
            applyFocusAssignment(isInspectorVisible ? .inspector : .none)
        }
    }

    private func handleInspectorVisibilityChange(
        _ newValue: Bool,
        inspectedPaneID: PaneID?,
        focusPaneTarget: (PaneID?) -> Void,
    ) {
        restoredInspectorVisible = newValue

        guard !newValue else {
            return
        }
        guard focusedTarget == .inspector else {
            return
        }

        focusPaneTarget(inspectedPaneID)
    }

    private func handleScenePhaseChange(_ newValue: ScenePhase) {
        switch newValue {
            case .inactive:
                workspaceStore.persistSceneStateNow(
                    reason: WorkspacePersistenceSaveReason.sceneBecameInactive,
                )
            case .background:
                workspaceStore.persistSceneStateNow(
                    reason: WorkspacePersistenceSaveReason.sceneEnteredBackground,
                )
            case .active:
                break
            @unknown default:
                break
        }
    }

    private func confirmWorkspaceDeletion(
        normalizeSelection: () -> Void,
    ) {
        guard let workspacePendingDeletionID else {
            Logger.diagnostics.error(
                "The app attempted to confirm workspace deletion in the active shell window, but no workspace was pending destructive confirmation.",
            )
            return
        }

        workspaceStore.deleteWorkspace(workspacePendingDeletionID)
        let deletedWorkspaceID = workspacePendingDeletionID.rawValue.uuidString
        Logger.diagnostics.notice(
            "Deleted a workspace after the active shell window confirmed the destructive action. Workspace ID: \(deletedWorkspaceID, privacy: .public)",
        )
        self.workspacePendingDeletionID = nil
        normalizeSelection()
    }

    private func saveWorkspaceRename() {
        guard let workspacePendingRenameID else {
            Logger.diagnostics.error(
                "The app attempted to save a workspace rename from the active shell window, but no workspace rename sheet was currently presented.",
            )
            return
        }

        workspaceStore.renameWorkspace(workspacePendingRenameID, to: workspaceRenameTitleDraft)
        selectedWorkspaceID = workspacePendingRenameID

        let renamedWorkspaceID = workspacePendingRenameID.rawValue.uuidString
        Logger.diagnostics.notice(
            "Saved a workspace rename from the active shell window. Workspace ID: \(renamedWorkspaceID, privacy: .public).",
        )
        Logger.diagnostics.notice(
            "The active shell window applied the latest workspace title change.",
        )

        self.workspacePendingRenameID = nil
    }

    private func normalizedPaneNavigationState(
        activePaneIDs: Set<PaneID>,
    ) -> (
        paneFrames: [PaneID: CGRect],
        paneFocusHistory: [PaneID],
        pendingFocusedPaneID: PaneID?,
        pendingHistoryPaneID: PaneID?,
    ) {
        let filteredPaneFrames = paneFrames.reduce(into: [PaneID: CGRect]()) { result, entry in
            if activePaneIDs.contains(entry.key) {
                result[entry.key] = entry.value
            }
        }
        let filteredPaneFocusHistory = paneFocusHistory.reduce(into: [PaneID]()) { result, paneID in
            if activePaneIDs.contains(paneID) {
                result.append(paneID)
            }
        }
        let normalizedPendingFocusedPaneID = pendingFocusedPaneID.flatMap {
            activePaneIDs.contains($0) ? $0 : nil
        }
        let normalizedPendingHistoryPaneID = pendingHistoryPaneID.flatMap {
            activePaneIDs.contains($0) ? $0 : nil
        }

        return (
            paneFrames: filteredPaneFrames,
            paneFocusHistory: filteredPaneFocusHistory,
            pendingFocusedPaneID: normalizedPendingFocusedPaneID,
            pendingHistoryPaneID: normalizedPendingHistoryPaneID,
        )
    }
}

enum UITestLaunchBehavior {
    private static let resetStateEnvironmentKey = WorkspacePersistenceProfile.uiTestResetStateEnvironmentKey

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[resetStateEnvironmentKey] == "1"
    }

    static func resetStateIfNeeded() {
        guard isEnabled else {
            return
        }

        let defaults = UserDefaults.standard
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleIdentifier)
        }
        defaults.synchronize()

        for cleanupURL in WorkspacePersistenceController.storeCleanupURLs(for: .uiTestOnDisk) {
            if FileManager.default.fileExists(atPath: cleanupURL.path) {
                try? FileManager.default.removeItem(at: cleanupURL)
            }
        }
    }
}

private struct PaneNavigationMetrics: Comparable {
    let hasPerpendicularOverlap: Bool
    let perpendicularOverlap: CGFloat
    let directionalDistance: CGFloat
    let perpendicularDistance: CGFloat
    let historyRank: Int

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.hasPerpendicularOverlap != rhs.hasPerpendicularOverlap {
            return !lhs.hasPerpendicularOverlap && rhs.hasPerpendicularOverlap
        }
        if lhs.perpendicularOverlap != rhs.perpendicularOverlap {
            return lhs.perpendicularOverlap < rhs.perpendicularOverlap
        }
        if lhs.directionalDistance != rhs.directionalDistance {
            return lhs.directionalDistance > rhs.directionalDistance
        }
        if lhs.perpendicularDistance != rhs.perpendicularDistance {
            return lhs.perpendicularDistance > rhs.perpendicularDistance
        }
        return lhs.historyRank < rhs.historyRank
    }
}

func directionalPaneFocus(
    from paneID: PaneID,
    paneFrames: [PaneID: CGRect],
    direction: PaneFocusDirection,
    history: [PaneID],
) -> PaneID? {
    guard let currentFrame = paneFrames[paneID] else {
        return nil
    }

    let candidates: [(PaneID, PaneNavigationMetrics)] = paneFrames.compactMap { candidatePaneID, candidateFrame in
        guard candidatePaneID != paneID else {
            return nil
        }
        guard let metrics = navigationMetrics(
            from: currentFrame,
            to: candidateFrame,
            direction: direction,
            history: history,
            paneID: candidatePaneID,
        ) else {
            return nil
        }

        return (candidatePaneID, metrics)
    }

    return candidates.max { lhs, rhs in
        lhs.1 < rhs.1
    }?.0
}

private func navigationMetrics(
    from currentFrame: CGRect,
    to candidateFrame: CGRect,
    direction: PaneFocusDirection,
    history: [PaneID],
    paneID: PaneID,
) -> PaneNavigationMetrics? {
    let directionalDistance: CGFloat
    let perpendicularOverlap: CGFloat
    let perpendicularDistance: CGFloat

    switch direction {
        case .left:
            guard candidateFrame.midX < currentFrame.midX else { return nil }

            directionalDistance = max(currentFrame.minX - candidateFrame.maxX, 0)
            perpendicularOverlap = overlapLength(
                currentMin: currentFrame.minY,
                currentMax: currentFrame.maxY,
                candidateMin: candidateFrame.minY,
                candidateMax: candidateFrame.maxY,
            )
            perpendicularDistance = abs(candidateFrame.midY - currentFrame.midY)

        case .right:
            guard candidateFrame.midX > currentFrame.midX else { return nil }

            directionalDistance = max(candidateFrame.minX - currentFrame.maxX, 0)
            perpendicularOverlap = overlapLength(
                currentMin: currentFrame.minY,
                currentMax: currentFrame.maxY,
                candidateMin: candidateFrame.minY,
                candidateMax: candidateFrame.maxY,
            )
            perpendicularDistance = abs(candidateFrame.midY - currentFrame.midY)

        case .up:
            guard candidateFrame.midY < currentFrame.midY else { return nil }

            directionalDistance = max(currentFrame.minY - candidateFrame.maxY, 0)
            perpendicularOverlap = overlapLength(
                currentMin: currentFrame.minX,
                currentMax: currentFrame.maxX,
                candidateMin: candidateFrame.minX,
                candidateMax: candidateFrame.maxX,
            )
            perpendicularDistance = abs(candidateFrame.midX - currentFrame.midX)

        case .down:
            guard candidateFrame.midY > currentFrame.midY else { return nil }

            directionalDistance = max(candidateFrame.minY - currentFrame.maxY, 0)
            perpendicularOverlap = overlapLength(
                currentMin: currentFrame.minX,
                currentMax: currentFrame.maxX,
                candidateMin: candidateFrame.minX,
                candidateMax: candidateFrame.maxX,
            )
            perpendicularDistance = abs(candidateFrame.midX - currentFrame.midX)

        case .next, .previous:
            return nil
    }

    let historyRank = history.lastIndex(of: paneID).map { history.distance(from: history.startIndex, to: $0) + 1 } ?? 0
    return PaneNavigationMetrics(
        hasPerpendicularOverlap: perpendicularOverlap > 0,
        perpendicularOverlap: perpendicularOverlap,
        directionalDistance: directionalDistance,
        perpendicularDistance: perpendicularDistance,
        historyRank: historyRank,
    )
}

private func overlapLength(
    currentMin: CGFloat,
    currentMax: CGFloat,
    candidateMin: CGFloat,
    candidateMax: CGFloat,
) -> CGFloat {
    max(0, min(currentMax, candidateMax) - max(currentMin, candidateMin))
}

func paneFocusTargetAfterClosingPane(
    closedPaneID: PaneID,
    focusedTarget: WorkspaceFocusTarget?,
    survivingPaneIDs: Set<PaneID>,
    paneFocusHistory: [PaneID],
    isInspectorVisible: Bool,
) -> WorkspaceFocusTarget? {
    let shouldRepairFocus = focusedTarget == .pane(closedPaneID) || {
        guard case let .pane(currentPaneID) = focusedTarget else {
            return false
        }

        return !survivingPaneIDs.contains(currentPaneID)
    }()

    guard shouldRepairFocus else {
        return focusedTarget
    }

    if let historyFallbackPaneID = paneFocusHistory.last(where: survivingPaneIDs.contains) {
        return .pane(historyFallbackPaneID)
    }

    if isInspectorVisible {
        return .inspector
    }

    return nil
}

private struct WorkspaceWindowPresentationModifier: ViewModifier {
    let workspaceStore: WorkspaceStore
    @Binding var selectedWorkspaceID: WorkspaceID?
    @Binding var isLibraryPresented: Bool
    let deleteAlertIsPresented: Binding<Bool>
    let deleteWorkspaceTitle: String?
    let confirmDelete: () -> Void
    let cancelDelete: () -> Void
    let renameSheetIsPresented: Binding<Bool>
    @Binding var workspaceRenameTitleDraft: String

    let cancelRename: () -> Void
    let saveRename: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isLibraryPresented) {
                LibrarySheet(
                    model: workspaceStore,
                    selectedWorkspaceID: $selectedWorkspaceID,
                )
            }
            .alert(
                "Delete Workspace?",
                isPresented: deleteAlertIsPresented,
            ) {
                Button("Delete", role: .destructive) {
                    confirmDelete()
                }
                .accessibilityIdentifier("sidebar.deleteWorkspaceConfirmButton")

                Button("Cancel", role: .cancel) {
                    cancelDelete()
                }
                .accessibilityIdentifier("sidebar.deleteWorkspaceCancelButton")
            } message: {
                Text(
                    "Delete “\(deleteWorkspaceTitle ?? "this workspace")” and close every pane in it? Your other workspaces stay open.",
                )
            }
            .sheet(isPresented: renameSheetIsPresented) {
                WorkspaceRenameSheet(
                    title: $workspaceRenameTitleDraft,
                    onCancel: {
                        cancelRename()
                    },
                    onSave: {
                        saveRename()
                    },
                )
            }
    }
}

private struct WorkspaceWindowLifecycleModifier: ViewModifier {
    let normalizedBackgroundSaveIntervalMinutes: Int
    let onInitialTask: () -> Void
    let onBackgroundSaveTask: @Sendable () async -> Void
    let onWillTerminate: () -> Void
    let selectedWorkspaceIDString: String?
    let onSelectedWorkspaceIDStringChange: (String?) -> Void
    let focusedTarget: WorkspaceFocusTarget?
    let onFocusedTargetChange: (WorkspaceFocusTarget?) -> Void
    let workspaceIDs: [UUID]
    let onWorkspaceIDsChange: () -> Void
    let selectedWorkspaceID: WorkspaceID?
    let onSelectedWorkspaceChange: () -> Void
    let selectedWorkspacePaneIDs: [PaneID]
    let onSelectedWorkspacePaneChange: ([PaneID]) -> Void
    let isInspectorVisible: Bool
    let onInspectorVisibilityChange: (Bool) -> Void
    let columnVisibility: NavigationSplitViewVisibility
    let onColumnVisibilityChange: (NavigationSplitViewVisibility) -> Void
    let scenePhase: ScenePhase
    let onScenePhaseChange: (ScenePhase) -> Void
    let appearsActive: Bool
    let onAppearsActiveChange: (Bool) -> Void
    let onDisappear: () -> Void

    func body(content: Content) -> some View {
        content
            .task {
                onInitialTask()
            }
            .task(id: normalizedBackgroundSaveIntervalMinutes) {
                await onBackgroundSaveTask()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                onWillTerminate()
            }
            .onChange(of: selectedWorkspaceIDString) { _, newValue in
                onSelectedWorkspaceIDStringChange(newValue)
            }
            .onChange(of: focusedTarget) { _, newValue in
                onFocusedTargetChange(newValue)
            }
            .onChange(of: workspaceIDs) { _, _ in
                onWorkspaceIDsChange()
            }
            .onChange(of: selectedWorkspaceID) { _, _ in
                onSelectedWorkspaceChange()
            }
            .onChange(of: selectedWorkspacePaneIDs) { _, paneIDs in
                onSelectedWorkspacePaneChange(paneIDs)
            }
            .onChange(of: isInspectorVisible) { _, newValue in
                onInspectorVisibilityChange(newValue)
            }
            .onChange(of: columnVisibility) { _, newValue in
                onColumnVisibilityChange(newValue)
            }
            .onChange(of: scenePhase) { _, newValue in
                onScenePhaseChange(newValue)
            }
            .onChange(of: appearsActive) { _, newValue in
                onAppearsActiveChange(newValue)
            }
            .onDisappear {
                onDisappear()
            }
    }
}

func paneFocusTargetAfterActivatingWindow(
    focusedTarget: WorkspaceFocusTarget?,
    survivingPaneIDs: Set<PaneID>,
    paneFocusHistory: [PaneID],
    isInspectorVisible: Bool,
    hasPresentedWorkspaceModal: Bool,
) -> WorkspaceFocusTarget? {
    guard !hasPresentedWorkspaceModal else {
        return focusedTarget
    }

    switch focusedTarget {
        case let .pane(paneID)? where survivingPaneIDs.contains(paneID):
            return .pane(paneID)
        case .inspector? where isInspectorVisible:
            return .inspector
        default:
            break
    }

    if let historyFallbackPaneID = paneFocusHistory.last(where: survivingPaneIDs.contains) {
        return .pane(historyFallbackPaneID)
    }

    return nil
}
