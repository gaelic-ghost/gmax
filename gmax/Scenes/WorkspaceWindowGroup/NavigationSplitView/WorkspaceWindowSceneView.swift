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
    @FocusState private var focusedTarget: WorkspaceFocusTarget?
    @SceneStorage(WorkspaceWindowSceneStorageKey.selectedWorkspaceID) private var restoredSelectedWorkspaceID: String?
    @SceneStorage(WorkspaceWindowSceneStorageKey.isInspectorVisible) private var restoredInspectorVisible = true
    @SceneStorage(WorkspaceWindowSceneStorageKey.isSidebarVisible) private var restoredSidebarVisible = true
    @State private var selectedWorkspaceID: WorkspaceID?
    @State private var workspacePendingDeletionID: WorkspaceID?
    @State private var workspacePendingRenameID: WorkspaceID?
    @State private var workspaceRenameTitleDraft = ""
    @State private var isSavedWorkspaceLibraryPresented = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isInspectorVisible = true
    @State private var hasAppliedSceneState = false
    @State private var paneFrames: [PaneID: CGRect] = [:]
    @State private var paneFocusHistory: [PaneID] = []
    @State private var pendingFocusedPaneID: PaneID?
    @State private var pendingHistoryPaneID: PaneID?
    @StateObject private var workspaceStore: WorkspaceStore

    private let sceneIdentity: WorkspaceSceneIdentity

    init(sceneIdentity: WorkspaceSceneIdentity = WorkspaceSceneIdentity()) {
        self.sceneIdentity = sceneIdentity
        _workspaceStore = StateObject(
            wrappedValue: WorkspaceStore(sceneIdentity: sceneIdentity),
        )
    }

    var body: some View {
        let openSavedWorkspaceLibrary = {
            isSavedWorkspaceLibraryPresented = true
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
            if isSavedWorkspaceLibraryPresented {
                return {
                    Logger.diagnostics.notice(
                        "Dismissed the saved-workspace library sheet from the active shell window without reopening a workspace.",
                    )
                    isSavedWorkspaceLibraryPresented = false
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
        let createPaneInWorkspace: (WorkspaceID) -> Void = { workspaceID in
            let createdPaneID = workspaceStore.createPane(in: workspaceID)
            prunePaneNavigationState()
            requestPaneFocus(createdPaneID)
        }
        let splitPaneInWorkspace: (WorkspaceID, PaneID, SplitDirection) -> Void = { workspaceID, paneID, direction in
            let insertedPaneID = workspaceStore.splitPane(paneID, in: workspaceID, direction: direction)
            prunePaneNavigationState()
            requestPaneFocus(insertedPaneID)
        }
        let closePaneInWorkspace: (WorkspaceID, PaneID) -> Void = { workspaceID, paneID in
            workspaceStore.closePane(paneID, in: workspaceID)
            prunePaneNavigationState()
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
            requestPaneFocus(insertedPaneID)
        }
        let canSplitFocusedPane = selectedWorkspace.flatMap { workspace in
            focusedPaneID.flatMap { workspace.root?.findPane(id: $0) }
        } != nil
        let moveFocusedPaneFocusAction = focusedPaneID == nil ? nil : moveFocusedPaneFocus
        let splitFocusedPaneAction: ((SplitDirection) -> Void)? = canSplitFocusedPane ? splitFocusedPane : nil
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
                requestRenameWorkspace: presentWorkspaceRename,
                requestDeleteWorkspace: presentWorkspaceDeletion,
            )
            .navigationSplitViewColumnWidth(220)
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
            )
            .navigationSplitViewColumnWidth(min: 640, ideal: 920)
        }
        .inspector(isPresented: $isInspectorVisible) {
            DetailPane(
                model: workspaceStore,
                selectedWorkspaceID: $selectedWorkspaceID,
                inspectedPaneID: inspectedPaneID,
                focusedTarget: $focusedTarget,
            )
            .inspectorColumnWidth(min: 220, ideal: 260, max: 340)
        }
        .sheet(isPresented: $isSavedWorkspaceLibraryPresented) {
            SavedWorkspaceLibrarySheet(model: workspaceStore, selectedWorkspaceID: $selectedWorkspaceID)
        }
        .alert(
            "Delete Workspace?",
            isPresented: Binding(
                get: { pendingDeletionWorkspace != nil },
                set: { isPresented in
                    if !isPresented {
                        dismissWorkspaceDeletion()
                    }
                },
            ),
            presenting: pendingDeletionWorkspace,
        ) { _ in
            Button("Delete", role: .destructive) {
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
            .accessibilityIdentifier("sidebar.deleteWorkspaceConfirmButton")

            Button("Cancel", role: .cancel) {
                dismissWorkspaceDeletion()
            }
            .accessibilityIdentifier("sidebar.deleteWorkspaceCancelButton")
        } message: { workspace in
            Text("Delete “\(workspace.title)” and close every pane in it? Your other workspaces stay open.")
        }
        .sheet(isPresented: Binding(
            get: { pendingRenameWorkspace != nil },
            set: { isPresented in
                if !isPresented {
                    dismissWorkspaceRename()
                }
            },
        )) {
            WorkspaceRenameSheet(
                title: $workspaceRenameTitleDraft,
                onCancel: {
                    dismissWorkspaceRename()
                },
                onSave: {
                    guard let workspacePendingRenameID else {
                        Logger.diagnostics.error(
                            "The app attempted to save a workspace rename from the active shell window, but no workspace rename sheet was currently presented.",
                        )
                        return
                    }

                    workspaceStore.renameWorkspace(workspacePendingRenameID, to: workspaceRenameTitleDraft)
                    selectedWorkspaceID = workspacePendingRenameID
                    Logger.diagnostics.notice(
                        "Saved a workspace rename from the active shell window. Workspace ID: \(workspacePendingRenameID.rawValue.uuidString, privacy: .public). New title: \(workspaceRenameTitleDraft, privacy: .public)",
                    )
                    self.workspacePendingRenameID = nil
                },
            )
        }
        .focusedSceneObject(workspaceStore)
        .focusedSceneValue(\.activeWorkspaceFocusTarget, focusedTarget)
        .focusedSceneValue(\.selectedWorkspaceSelection, $selectedWorkspaceID)
        .focusedSceneValue(\.dismissPresentedWorkspaceModal, dismissPresentedWorkspaceModal)
        .focusedSceneValue(\.openSavedWorkspaceLibrary, openSavedWorkspaceLibrary)
        .focusedSceneValue(\.presentWorkspaceRename, presentWorkspaceRename)
        .focusedSceneValue(\.presentWorkspaceDeletion, presentWorkspaceDeletion)
        .focusedSceneValue(\.moveFocusedPaneFocus, moveFocusedPaneFocusAction)
        .focusedSceneValue(\.splitFocusedPane, splitFocusedPaneAction)
        .focusedSceneValue(\.closeFocusedPane, closeFocusedPaneAction)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Open Saved Workspaces", systemImage: "folder", action: openSavedWorkspaceLibrary)
                    .labelStyle(.iconOnly)
                    .help("Open saved workspaces (\u{2318}O)")
                    .accessibilityIdentifier("workspaceWindow.openSavedWorkspacesButton")
            }

            ToolbarItem(placement: .navigation) {
                Button("New Workspace", systemImage: "plus.rectangle.on.rectangle") {
                    selectedWorkspaceID = workspaceStore.createWorkspace()
                }
                .labelStyle(.iconOnly)
                .help("Create a new workspace (\u{2318}N)")
                .accessibilityIdentifier("workspaceWindow.newWorkspaceButton")
            }

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
                    isInspectorVisible.toggle()
                    Logger.diagnostics.notice(
                        "Toggled inspector visibility in the active shell window. Inspector is now \(isInspectorVisible ? "visible" : "hidden", privacy: .public).",
                    )
                }
                .labelStyle(.iconOnly)
                .help(isInspectorVisible ? "Hide the inspector (\u{21E7}\u{2318}B)" : "Show the inspector (\u{21E7}\u{2318}B)")
                .accessibilityIdentifier("workspaceWindow.toggleInspectorButton")
            }
        }
        .task {
            guard !hasAppliedSceneState else {
                return
            }

            hasAppliedSceneState = true
            let restoredSelection = restoredSelectedWorkspaceID
                .flatMap(UUID.init(uuidString:))
                .map { WorkspaceID(rawValue: $0) }
            selectedWorkspaceID = restoredSelection ?? workspaceStore.workspaces.first?.id
            normalizeSelection()
            columnVisibility = restoredSidebarVisible ? .all : .doubleColumn
            isInspectorVisible = restoredInspectorVisible
            Logger.diagnostics.notice(
                """
                Applied per-window shell scene restoration. Restored workspace selection: \(restoredSelection?.rawValue.uuidString ?? "(none)", privacy: .public). \
                Normalized workspace selection: \(selectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public). \
                Sidebar visibility: \(restoredSidebarVisible ? "visible" : "hidden", privacy: .public). \
                Inspector visibility: \(restoredInspectorVisible ? "visible" : "hidden", privacy: .public).
                """,
            )
        }
        .onChange(of: selectedWorkspaceID?.rawValue.uuidString) { _, newValue in
            restoredSelectedWorkspaceID = newValue
        }
        .onChange(of: focusedTarget) { _, newValue in
            guard case let .pane(paneID) = newValue, activePaneIDs.contains(paneID) else {
                pendingHistoryPaneID = nil
                return
            }

            recordFocusedPaneInHistory(paneID)
        }
        .onChange(of: workspaceStore.workspaces.map(\.id.rawValue)) { _, _ in
            normalizeSelection()
        }
        .onChange(of: selectedWorkspaceID) { _, _ in
            paneFrames = [:]
            paneFocusHistory = []
            pendingFocusedPaneID = nil
            pendingHistoryPaneID = nil
        }
        .onChange(of: selectedWorkspace?.paneLeaves.map(\.id) ?? []) { _, paneIDs in
            let activePaneIDs = Set(paneIDs)
            paneFrames = paneFrames.filter { activePaneIDs.contains($0.key) }
            paneFocusHistory = paneFocusHistory.filter { activePaneIDs.contains($0) }
            pendingFocusedPaneID = pendingFocusedPaneID.flatMap { activePaneIDs.contains($0) ? $0 : nil }
            pendingHistoryPaneID = pendingHistoryPaneID.flatMap { activePaneIDs.contains($0) ? $0 : nil }
            if case let .pane(paneID) = focusedTarget, !activePaneIDs.contains(paneID) {
                applyFocusAssignment(isInspectorVisible ? .inspector : .none)
            }
        }
        .onChange(of: isInspectorVisible) { _, newValue in
            restoredInspectorVisible = newValue
            if !newValue, focusedTarget == .inspector {
                focusPaneTarget(inspectedPaneID)
            }
        }
        .onChange(of: columnVisibility) { _, newValue in
            restoredSidebarVisible = newValue == .all
        }
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
