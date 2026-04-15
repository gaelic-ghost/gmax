import OSLog
import SwiftUI

struct WorkspaceWindowSceneView: View {
	@StateObject private var workspaceStore = WorkspaceStore()
	@State private var selectedWorkspaceID: WorkspaceID?
	@State private var workspacePendingDeletionID: WorkspaceID?
	@State private var workspacePendingRenameID: WorkspaceID?
	@State private var workspaceRenameTitleDraft = ""
	@State private var isSavedWorkspaceLibraryPresented = false
	@State private var columnVisibility: NavigationSplitViewVisibility = .all
	@State private var isInspectorVisible = true
	@SceneStorage("mainShell.selectedWorkspaceID") private var restoredSelectedWorkspaceID: String?
	@SceneStorage("mainShell.isInspectorVisible") private var restoredInspectorVisible = true
	@SceneStorage("mainShell.isSidebarVisible") private var restoredSidebarVisible = true
	@State private var hasAppliedSceneState = false

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
					"Dismissed workspace deletion confirmation without deleting the workspace. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)"
				)
			}
			self.workspacePendingDeletionID = nil
		}
		let dismissWorkspaceRename = {
			if let workspacePendingRenameID {
				Logger.diagnostics.notice(
					"Dismissed the workspace rename sheet without saving changes. Workspace ID: \(workspacePendingRenameID.rawValue.uuidString, privacy: .public)"
				)
			}
			workspacePendingRenameID = nil
		}
		let presentWorkspaceRename: (WorkspaceID) -> Void = { workspaceID in
			guard let workspace = workspaceStore.workspaces.first(where: { $0.id == workspaceID }) else {
				Logger.diagnostics.notice(
					"Skipped presenting the workspace rename sheet because the requested workspace no longer exists in the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
				)
				return
			}

			workspaceRenameTitleDraft = workspace.title
			workspacePendingRenameID = workspace.id
			selectedWorkspaceID = workspace.id
			Logger.diagnostics.notice(
				"Presented the workspace rename sheet for the active shell window. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)"
			)
		}
		let presentWorkspaceDeletion: (WorkspaceID) -> Void = { workspaceID in
			guard workspaceStore.workspaces.count > 1, workspaceStore.workspaces.contains(where: { $0.id == workspaceID }) else {
				Logger.diagnostics.notice(
					"Skipped presenting workspace deletion confirmation because the selected workspace cannot be deleted safely. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
				)
				return
			}

			workspacePendingDeletionID = workspaceID
			Logger.diagnostics.notice(
				"Presented workspace deletion confirmation for the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
		}
		let pendingDeletionWorkspace = workspacePendingDeletionID.flatMap { workspaceID in workspaceStore.workspaces.first { $0.id == workspaceID } }
		let pendingRenameWorkspace = workspacePendingRenameID.flatMap { workspaceID in workspaceStore.workspaces.first { $0.id == workspaceID } }
		let canSplitFocusedPane = selectedWorkspaceID
			.flatMap { selectedWorkspaceID in workspaceStore.workspaces.first { $0.id == selectedWorkspaceID } }
			.flatMap { workspace in
				workspace.focusedPaneID.flatMap { workspace.root?.findPane(id: $0) }
			} != nil

		NavigationSplitView(columnVisibility: $columnVisibility) {
			SidebarPane(
				model: workspaceStore,
				selection: $selectedWorkspaceID,
				requestRenameWorkspace: presentWorkspaceRename,
				requestDeleteWorkspace: presentWorkspaceDeletion
			)
			.navigationSplitViewColumnWidth(220)
		} detail: {
			ContentPane(model: workspaceStore, selectedWorkspaceID: $selectedWorkspaceID)
				.navigationSplitViewColumnWidth(min: 640, ideal: 920)
		}
		.inspector(isPresented: $isInspectorVisible) {
			DetailPane(model: workspaceStore, selectedWorkspaceID: $selectedWorkspaceID)
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
				}
			),
			presenting: pendingDeletionWorkspace
		) { _ in
			Button("Delete", role: .destructive) {
				guard let workspacePendingDeletionID else {
					Logger.diagnostics.error(
						"The app attempted to confirm workspace deletion in the active shell window, but no workspace was pending destructive confirmation."
					)
					return
				}

				workspaceStore.deleteWorkspace(workspacePendingDeletionID)
				let deletedWorkspaceID = workspacePendingDeletionID.rawValue.uuidString
				Logger.diagnostics.notice(
					"Deleted a workspace after the active shell window confirmed the destructive action. Workspace ID: \(deletedWorkspaceID, privacy: .public)"
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
			}
		)) {
			WorkspaceRenameSheet(
				title: $workspaceRenameTitleDraft,
				onCancel: {
					dismissWorkspaceRename()
				},
				onSave: {
					guard let workspacePendingRenameID else {
						Logger.diagnostics.error(
							"The app attempted to save a workspace rename from the active shell window, but no workspace rename sheet was currently presented."
						)
						return
					}

					workspaceStore.renameWorkspace(workspacePendingRenameID, to: workspaceRenameTitleDraft)
					selectedWorkspaceID = workspacePendingRenameID
					Logger.diagnostics.notice(
						"Saved a workspace rename from the active shell window. Workspace ID: \(workspacePendingRenameID.rawValue.uuidString, privacy: .public). New title: \(workspaceRenameTitleDraft, privacy: .public)"
					)
					self.workspacePendingRenameID = nil
				}
			)
		}
		.focusedSceneObject(workspaceStore)
		.focusedSceneValue(\.selectedWorkspaceSelection, $selectedWorkspaceID)
		.focusedSceneValue(\.openSavedWorkspaceLibrary, openSavedWorkspaceLibrary)
		.focusedSceneValue(\.presentWorkspaceRename, presentWorkspaceRename)
		.focusedSceneValue(\.presentWorkspaceDeletion, presentWorkspaceDeletion)
		.toolbar {
			ToolbarItem(placement: .navigation) {
				Button("Open Saved Workspaces", systemImage: "folder", action: openSavedWorkspaceLibrary)
				.labelStyle(.iconOnly)
				.help("Open saved workspaces (\u{2318}O)")
				.accessibilityIdentifier("mainShell.openSavedWorkspacesButton")
			}

			ToolbarItem(placement: .navigation) {
				Button("New Workspace", systemImage: "plus.rectangle.on.rectangle") {
					selectedWorkspaceID = workspaceStore.createWorkspace()
				}
				.labelStyle(.iconOnly)
				.help("Create a new workspace (\u{2318}N)")
				.accessibilityIdentifier("mainShell.newWorkspaceButton")
			}

			ToolbarItemGroup(placement: .primaryAction) {
				Button("Split Right", systemImage: "uiwindow.split.2x1") {
					if let selectedWorkspaceID {
						workspaceStore.splitFocusedPane(in: selectedWorkspaceID, .right)
					}
				}
				.labelStyle(.iconOnly)
				.help("Split the focused pane to the right (\u{2318}D)")
				.disabled(!canSplitFocusedPane)
				.accessibilityIdentifier("mainShell.splitRightButton")

				Button("Split Down", systemImage: "uiwindow.split.2x1.rotate.90") {
					if let selectedWorkspaceID {
						workspaceStore.splitFocusedPane(in: selectedWorkspaceID, .down)
					}
				}
				.labelStyle(.iconOnly)
				.help("Split the focused pane downward (\u{21E7}\u{2318}D)")
				.disabled(!canSplitFocusedPane)
				.accessibilityIdentifier("mainShell.splitDownButton")
			}

			ToolbarItem(placement: .primaryAction) {
				Button(
					isInspectorVisible ? "Hide Inspector" : "Show Inspector",
					systemImage: "sidebar.right"
				) {
					isInspectorVisible.toggle()
					Logger.diagnostics.notice(
						"Toggled inspector visibility in the active shell window. Inspector is now \(isInspectorVisible ? "visible" : "hidden", privacy: .public)."
					)
				}
				.labelStyle(.iconOnly)
				.help(isInspectorVisible ? "Hide the inspector (\u{21E7}\u{2318}B)" : "Show the inspector (\u{21E7}\u{2318}B)")
				.accessibilityIdentifier("mainShell.toggleInspectorButton")
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
				"""
			)
		}
		.onChange(of: selectedWorkspaceID?.rawValue.uuidString) { _, newValue in
			restoredSelectedWorkspaceID = newValue
		}
		.onChange(of: workspaceStore.workspaces.map(\.id.rawValue)) { _, _ in
			normalizeSelection()
		}
		.onChange(of: isInspectorVisible) { _, newValue in
			restoredInspectorVisible = newValue
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
