//
//  gmaxApp+WindowView.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import OSLog
import SwiftUI

struct MainShellWindowView: View {
	@StateObject private var shellModel = ShellModel()
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
	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	var body: some View {
		NavigationSplitView(columnVisibility: $columnVisibility) {
			SidebarPane(
				model: shellModel,
				selection: $selectedWorkspaceID,
				requestRenameWorkspace: { workspaceID in
					presentWorkspaceRename(for: workspaceID)
				},
				requestDeleteWorkspace: { workspaceID in
					presentWorkspaceDeletionConfirmation(for: workspaceID)
				}
			)
			.navigationSplitViewColumnWidth(220)
		} detail: {
			ContentPane(model: shellModel, selectedWorkspaceID: $selectedWorkspaceID)
				.navigationSplitViewColumnWidth(min: 640, ideal: 920)
		}
		.inspector(isPresented: $isInspectorVisible) {
			DetailPane(model: shellModel, selectedWorkspaceID: $selectedWorkspaceID)
				.inspectorColumnWidth(
					min: 220,
					ideal: 260,
					max: 340
				)
		}
		.sheet(isPresented: $isSavedWorkspaceLibraryPresented) {
			SavedWorkspaceLibrarySheet(
				model: shellModel,
				selectedWorkspaceID: $selectedWorkspaceID
			)
		}
		.alert(
			"Delete Workspace?",
			isPresented: deleteWorkspaceAlertBinding,
			presenting: pendingDeletionWorkspace
		) { _ in
			Button("Delete", role: .destructive) {
				confirmWorkspaceDeletion()
			}
			.accessibilityIdentifier("sidebar.deleteWorkspaceConfirmButton")

			Button("Cancel", role: .cancel) {
				cancelWorkspaceDeletion()
			}
			.accessibilityIdentifier("sidebar.deleteWorkspaceCancelButton")
		} message: { workspace in
			Text("Delete “\(workspace.title)” and close every pane in it? Your other workspaces stay open.")
		}
		.sheet(isPresented: renameWorkspaceSheetBinding) {
			WorkspaceRenameSheet(
				title: $workspaceRenameTitleDraft,
				onCancel: {
					cancelWorkspaceRename()
				},
				onSave: {
					confirmWorkspaceRename()
				}
			)
		}
		.focusedSceneObject(shellModel)
		.focusedSceneValue(\.selectedWorkspaceSelection, $selectedWorkspaceID)
		.focusedSceneValue(\.openSavedWorkspaceLibrary) {
			isSavedWorkspaceLibraryPresented = true
		}
		.focusedSceneValue(\.presentWorkspaceRename) { workspaceID in
			presentWorkspaceRename(for: workspaceID)
		}
		.focusedSceneValue(\.presentWorkspaceDeletion) { workspaceID in
			presentWorkspaceDeletionConfirmation(for: workspaceID)
		}
		.toolbar {
			ToolbarItem(placement: .navigation) {
				Button("Open Saved Workspaces", systemImage: "folder") {
					isSavedWorkspaceLibraryPresented = true
				}
				.labelStyle(.iconOnly)
				.help("Open saved workspaces (\u{2318}O)")
				.accessibilityIdentifier("mainShell.openSavedWorkspacesButton")
			}

			ToolbarItem(placement: .navigation) {
				Button("New Workspace", systemImage: "plus.rectangle.on.rectangle") {
					selectedWorkspaceID = shellModel.createWorkspace()
				}
				.labelStyle(.iconOnly)
				.help("Create a new workspace (\u{2318}N)")
				.accessibilityIdentifier("mainShell.newWorkspaceButton")
			}

			ToolbarItemGroup(placement: .primaryAction) {
				Button("Split Right", systemImage: "uiwindow.split.2x1") {
					splitFocusedPane(.right)
				}
				.labelStyle(.iconOnly)
				.help("Split the focused pane to the right (\u{2318}D)")
				.disabled(!canSplitFocusedPane)
				.accessibilityIdentifier("mainShell.splitRightButton")

				Button("Split Down", systemImage: "uiwindow.split.2x1.rotate.90") {
					splitFocusedPane(.down)
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
					toggleInspector()
				}
				.labelStyle(.iconOnly)
				.help(isInspectorVisible ? "Hide the inspector (\u{21E7}\u{2318}B)" : "Show the inspector (\u{21E7}\u{2318}B)")
				.accessibilityIdentifier("mainShell.toggleInspectorButton")
			}
		}
		.task {
			applySceneStateIfNeeded()
		}
		.onChange(of: selectedWorkspaceID?.rawValue.uuidString) { _, newValue in
			restoredSelectedWorkspaceID = newValue
		}
		.onChange(of: shellModel.workspaces.map(\.id.rawValue)) { _, _ in
			selectedWorkspaceID = normalizedSelectedWorkspaceID(selectedWorkspaceID)
		}
		.onChange(of: isInspectorVisible) { _, newValue in
			restoredInspectorVisible = newValue
		}
		.onChange(of: columnVisibility) { _, newValue in
			restoredSidebarVisible = newValue == .all
		}
	}

	private var pendingDeletionWorkspace: Workspace? {
		guard let workspacePendingDeletionID else {
			return nil
		}
		return shellModel.workspaces.first(where: { $0.id == workspacePendingDeletionID })
	}

	private var pendingRenameWorkspace: Workspace? {
		guard let workspacePendingRenameID else {
			return nil
		}
		return shellModel.workspaces.first(where: { $0.id == workspacePendingRenameID })
	}

	private var canSplitFocusedPane: Bool {
		guard let selectedWorkspaceID else {
			return false
		}
		guard
			let workspace = shellModel.workspaces.first(where: { $0.id == selectedWorkspaceID }),
			let focusedPaneID = workspace.focusedPaneID
		else {
			return false
		}
		return workspace.root?.findPane(id: focusedPaneID) != nil
	}

	private func applySceneStateIfNeeded() {
		guard !hasAppliedSceneState else {
			return
		}

		hasAppliedSceneState = true
		let restoredSelection = restoredSelectedWorkspaceID
			.flatMap(UUID.init(uuidString:))
			.map { WorkspaceID(rawValue: $0) }
		selectedWorkspaceID = normalizedSelectedWorkspaceID(restoredSelection ?? shellModel.workspaces.first?.id)
		columnVisibility = restoredSidebarVisible ? .all : .doubleColumn
		isInspectorVisible = restoredInspectorVisible
		diagnosticsLogger.notice(
   """
   Applied per-window shell scene restoration. Restored workspace selection: \(restoredSelection?.rawValue.uuidString ?? "(none)", privacy: .public). \
   Normalized workspace selection: \(selectedWorkspaceID?.rawValue.uuidString ?? "(none)", privacy: .public). \
   Sidebar visibility: \(restoredSidebarVisible ? "visible" : "hidden", privacy: .public). \
   Inspector visibility: \(restoredInspectorVisible ? "visible" : "hidden", privacy: .public).
   """
		)
	}

	private func splitFocusedPane(_ direction: SplitDirection) {
		guard let selectedWorkspaceID else {
			return
		}
		shellModel.splitFocusedPane(in: selectedWorkspaceID, direction)
	}

	private func presentWorkspaceDeletionConfirmation(for workspaceID: WorkspaceID) {
		guard shellModel.canDeleteWorkspace(workspaceID) else {
			diagnosticsLogger.notice(
				"Skipped presenting workspace deletion confirmation because the selected workspace cannot be deleted safely. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
			return
		}

		workspacePendingDeletionID = workspaceID
		diagnosticsLogger.notice(
			"Presented workspace deletion confirmation for the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
		)
	}

	private func cancelWorkspaceDeletion() {
		guard let workspacePendingDeletionID else {
			return
		}

		diagnosticsLogger.notice(
			"Dismissed workspace deletion confirmation without deleting the workspace. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)"
		)
		self.workspacePendingDeletionID = nil
	}

	private func confirmWorkspaceDeletion() {
		guard let workspacePendingDeletionID else {
			diagnosticsLogger.error(
				"The app attempted to confirm workspace deletion in the active shell window, but no workspace was pending destructive confirmation."
			)
			return
		}

		shellModel.deleteWorkspace(workspacePendingDeletionID)
		diagnosticsLogger.notice(
			"Deleted a workspace after the active shell window confirmed the destructive action. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)"
		)
		self.workspacePendingDeletionID = nil
		selectedWorkspaceID = normalizedSelectedWorkspaceID(selectedWorkspaceID)
	}

	private func presentWorkspaceRename(for workspaceID: WorkspaceID) {
		guard let workspace = shellModel.workspaces.first(where: { $0.id == workspaceID }) else {
			diagnosticsLogger.notice(
				"Skipped presenting the workspace rename sheet because the requested workspace no longer exists in the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
			return
		}

		workspaceRenameTitleDraft = workspace.title
		workspacePendingRenameID = workspace.id
		selectedWorkspaceID = workspace.id
		diagnosticsLogger.notice(
			"Presented the workspace rename sheet for the active shell window. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)"
		)
	}

	private func cancelWorkspaceRename() {
		guard let pendingWorkspaceID = workspacePendingRenameID else {
			return
		}

		diagnosticsLogger.notice(
			"Dismissed the workspace rename sheet without saving changes. Workspace ID: \(pendingWorkspaceID.rawValue.uuidString, privacy: .public)"
		)
		workspacePendingRenameID = nil
	}

	private func confirmWorkspaceRename() {
		guard let pendingWorkspaceID = workspacePendingRenameID else {
			diagnosticsLogger.error(
				"The app attempted to save a workspace rename from the active shell window, but no workspace rename sheet was currently presented."
			)
			return
		}

		shellModel.renameWorkspace(pendingWorkspaceID, to: workspaceRenameTitleDraft)
		selectedWorkspaceID = pendingWorkspaceID
		diagnosticsLogger.notice(
			"Saved a workspace rename from the active shell window. Workspace ID: \(pendingWorkspaceID.rawValue.uuidString, privacy: .public). New title: \(workspaceRenameTitleDraft, privacy: .public)"
		)
		workspacePendingRenameID = nil
	}

	private func toggleInspector() {
		isInspectorVisible.toggle()
		let inspectorVisibilityDescription = isInspectorVisible ? "visible" : "hidden"
		diagnosticsLogger.notice(
			"Toggled inspector visibility in the active shell window. Inspector is now \(inspectorVisibilityDescription, privacy: .public)."
		)
	}

	private var deleteWorkspaceAlertBinding: Binding<Bool> {
		Binding(
			get: { pendingDeletionWorkspace != nil },
			set: { isPresented in
				if !isPresented {
					cancelWorkspaceDeletion()
				}
			}
		)
	}

	private var renameWorkspaceSheetBinding: Binding<Bool> {
		Binding(
			get: { pendingRenameWorkspace != nil },
			set: { isPresented in
				if !isPresented {
					cancelWorkspaceRename()
				}
			}
		)
	}

	private func normalizedSelectedWorkspaceID(_ workspaceID: WorkspaceID?) -> WorkspaceID? {
		if let workspaceID, shellModel.workspaces.contains(where: { $0.id == workspaceID }) {
			return workspaceID
		}
		return shellModel.workspaces.first?.id
	}
}

enum UITestLaunchBehavior {
	private static let resetStateEnvironmentKey = "GMAX_UI_TEST_RESET_STATE"

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

		let storeURL = ShellPersistenceController.storeURL()
		for cleanupURL in [storeURL, storeURL.appendingPathExtension("shm"), storeURL.appendingPathExtension("wal")] {
			if FileManager.default.fileExists(atPath: cleanupURL.path) {
				try? FileManager.default.removeItem(at: cleanupURL)
			}
		}
	}
}
