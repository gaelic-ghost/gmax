//
//  MainShellSceneView.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import OSLog
import SwiftUI

struct MainShellSceneView: View {
	@StateObject private var shellModel: ShellModel
	@State private var sceneContext: MainShellSceneContext
	@State private var selectedWorkspaceID: WorkspaceID?
	@SceneStorage("mainShell.selectedWorkspaceID") private var restoredSelectedWorkspaceID: String?
	@SceneStorage("mainShell.isInspectorVisible") private var restoredInspectorVisible = true
	@SceneStorage("mainShell.isSidebarVisible") private var restoredSidebarVisible = true
	@State private var hasAppliedSceneState = false
	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	private let sidebarColumnWidth: CGFloat = 220
	private let contentColumnIdealWidth: CGFloat = 920
	private let inspectorColumnMinimumWidth: CGFloat = 220
	private let inspectorColumnIdealWidth: CGFloat = 260
	private let inspectorColumnMaximumWidth: CGFloat = 340

	init() {
		let shellModel = ShellModel()
		_shellModel = StateObject(wrappedValue: shellModel)
		_selectedWorkspaceID = State(initialValue: shellModel.normalizedWorkspaceSelection(nil))
		_sceneContext = State(
			initialValue: MainShellSceneContext(
				shellModel: shellModel
			)
		)
	}

	var body: some View {
		@Bindable var bindableSceneContext = sceneContext

		NavigationSplitView(columnVisibility: $bindableSceneContext.columnVisibility) {
			SidebarPane(
				model: shellModel,
				selection: workspaceSelection,
				requestRenameWorkspace: { workspaceID in
					presentWorkspaceRename(for: workspaceID)
				},
				requestDeleteWorkspace: { workspaceID in
					presentWorkspaceDeletionConfirmation(for: workspaceID)
				}
			)
				.navigationSplitViewColumnWidth(sidebarColumnWidth)
		} detail: {
			ContentPane(model: shellModel, selectedWorkspaceID: workspaceSelection)
				.navigationSplitViewColumnWidth(min: 640, ideal: contentColumnIdealWidth)
		}
		.inspector(isPresented: $bindableSceneContext.isInspectorVisible) {
			DetailPane(model: shellModel, selectedWorkspaceID: workspaceSelection)
				.inspectorColumnWidth(
					min: inspectorColumnMinimumWidth,
					ideal: inspectorColumnIdealWidth,
					max: inspectorColumnMaximumWidth
				)
		}
		.sheet(isPresented: $bindableSceneContext.isSavedWorkspaceLibraryPresented) {
			SavedWorkspaceLibrarySheet(
				model: shellModel,
				selectedWorkspaceID: workspaceSelection
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
				title: $bindableSceneContext.workspaceRenameTitleDraft,
				onCancel: {
					cancelWorkspaceRename()
				},
				onSave: {
					confirmWorkspaceRename()
				}
			)
		}
		.focusedSceneValue(\.mainShellSceneContext, sceneContext)
		.focusedSceneValue(\.selectedWorkspaceSelection, workspaceSelection)
		.toolbar {
				ToolbarItem(placement: .navigation) {
					Button("Open Saved Workspaces", systemImage: "folder") {
						sceneContext.isSavedWorkspaceLibraryPresented = true
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
						sceneContext.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
						systemImage: "sidebar.right"
					) {
						toggleInspector()
					}
				.labelStyle(.iconOnly)
				.help(sceneContext.isInspectorVisible ? "Hide the inspector (\u{21E7}\u{2318}B)" : "Show the inspector (\u{21E7}\u{2318}B)")
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
				normalizeSelectionAfterWorkspaceMutation()
			}
		.onChange(of: sceneContext.isInspectorVisible) { _, newValue in
			restoredInspectorVisible = newValue
		}
		.onChange(of: sceneContext.columnVisibility) { _, newValue in
			restoredSidebarVisible = newValue == .all
		}
	}

	private var pendingDeletionWorkspace: Workspace? {
		guard let workspacePendingDeletionID = sceneContext.workspacePendingDeletionID else {
			return nil
		}
		return shellModel.workspace(for: workspacePendingDeletionID)
	}

	private var pendingRenameWorkspace: Workspace? {
		guard let workspacePendingRenameID = sceneContext.workspacePendingRenameID else {
			return nil
		}
		return shellModel.workspace(for: workspacePendingRenameID)
	}

	private var canSplitFocusedPane: Bool {
		guard let selectedWorkspaceID else {
			return false
		}
		return shellModel.focusedPane(in: selectedWorkspaceID) != nil
	}

	private var workspaceSelection: Binding<WorkspaceID?> {
		Binding(
			get: { selectedWorkspaceID },
			set: { newValue in
				selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(newValue)
			}
		)
	}

	private func applySceneStateIfNeeded() {
		guard !hasAppliedSceneState else {
			return
		}

		hasAppliedSceneState = true
		let restoredSelection = restoredSelectedWorkspaceID
			.flatMap(UUID.init(uuidString:))
			.map { WorkspaceID(rawValue: $0) }
		selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(
			restoredSelection ?? selectedWorkspaceID
		)
		sceneContext.columnVisibility = restoredSidebarVisible ? .all : .doubleColumn
		sceneContext.isInspectorVisible = restoredInspectorVisible
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

	private func normalizeSelectionAfterWorkspaceMutation() {
		selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(selectedWorkspaceID)
	}

	private func presentWorkspaceDeletionConfirmation(for workspaceID: WorkspaceID) {
		guard shellModel.canDeleteWorkspace(workspaceID) else {
			diagnosticsLogger.notice(
				"Skipped presenting workspace deletion confirmation because the selected workspace cannot be deleted safely. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
			return
		}

		sceneContext.workspacePendingDeletionID = workspaceID
		diagnosticsLogger.notice(
			"Presented workspace deletion confirmation for the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
		)
	}

	private func cancelWorkspaceDeletion() {
		guard let workspacePendingDeletionID = sceneContext.workspacePendingDeletionID else {
			return
		}

		diagnosticsLogger.notice(
			"Dismissed workspace deletion confirmation without deleting the workspace. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)"
		)
		sceneContext.workspacePendingDeletionID = nil
	}

	private func confirmWorkspaceDeletion() {
		guard let workspacePendingDeletionID = sceneContext.workspacePendingDeletionID else {
			diagnosticsLogger.error(
				"The app attempted to confirm workspace deletion in the active shell window, but no workspace was pending destructive confirmation."
			)
			return
		}

		shellModel.deleteWorkspace(workspacePendingDeletionID)
		diagnosticsLogger.notice(
			"Deleted a workspace after the active shell window confirmed the destructive action. Workspace ID: \(workspacePendingDeletionID.rawValue.uuidString, privacy: .public)"
		)
		sceneContext.workspacePendingDeletionID = nil
		normalizeSelectionAfterWorkspaceMutation()
	}

	private func presentWorkspaceRename(for workspaceID: WorkspaceID) {
		guard let workspace = shellModel.workspace(for: workspaceID) else {
			diagnosticsLogger.notice(
				"Skipped presenting the workspace rename sheet because the requested workspace no longer exists in the active shell window. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)"
			)
			return
		}

		sceneContext.workspaceRenameTitleDraft = workspace.title
		sceneContext.workspacePendingRenameID = workspace.id
		selectedWorkspaceID = workspace.id
		diagnosticsLogger.notice(
			"Presented the workspace rename sheet for the active shell window. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)"
		)
	}

	private func cancelWorkspaceRename() {
		guard let pendingWorkspaceID = sceneContext.workspacePendingRenameID else {
			return
		}

		diagnosticsLogger.notice(
			"Dismissed the workspace rename sheet without saving changes. Workspace ID: \(pendingWorkspaceID.rawValue.uuidString, privacy: .public)"
		)
		sceneContext.workspacePendingRenameID = nil
	}

	private func confirmWorkspaceRename() {
		guard let pendingWorkspaceID = sceneContext.workspacePendingRenameID else {
			diagnosticsLogger.error(
				"The app attempted to save a workspace rename from the active shell window, but no workspace rename sheet was currently presented."
			)
			return
		}

		shellModel.renameWorkspace(pendingWorkspaceID, to: sceneContext.workspaceRenameTitleDraft)
		selectedWorkspaceID = pendingWorkspaceID
		diagnosticsLogger.notice(
			"Saved a workspace rename from the active shell window. Workspace ID: \(pendingWorkspaceID.rawValue.uuidString, privacy: .public). New title: \(sceneContext.workspaceRenameTitleDraft, privacy: .public)"
		)
		sceneContext.workspacePendingRenameID = nil
	}

	private func toggleInspector() {
		sceneContext.isInspectorVisible.toggle()
		let inspectorVisibilityDescription = sceneContext.isInspectorVisible ? "visible" : "hidden"
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
}
