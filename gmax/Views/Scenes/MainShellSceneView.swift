//
//  MainShellSceneView.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import SwiftUI

struct MainShellSceneView: View {
	@ObservedObject var shellModel: ShellModel
	@State private var sceneContext: MainShellSceneContext
	@SceneStorage("mainShell.selectedWorkspaceID") private var restoredSelectedWorkspaceID: String?
	@SceneStorage("mainShell.isInspectorVisible") private var restoredInspectorVisible = true
	@SceneStorage("mainShell.isSidebarVisible") private var restoredSidebarVisible = true
	@State private var hasAppliedSceneState = false

	private let sidebarColumnWidth: CGFloat = 220
	private let contentColumnIdealWidth: CGFloat = 920
	private let inspectorColumnMinimumWidth: CGFloat = 220
	private let inspectorColumnIdealWidth: CGFloat = 260
	private let inspectorColumnMaximumWidth: CGFloat = 340

	init(shellModel: ShellModel) {
		self.shellModel = shellModel
		_sceneContext = State(
			initialValue: MainShellSceneContext(
				shellModel: shellModel,
				selectedWorkspaceID: shellModel.normalizedWorkspaceSelection(nil)
			)
		)
	}

	var body: some View {
		@Bindable var bindableSceneContext = sceneContext

		NavigationSplitView(columnVisibility: $bindableSceneContext.columnVisibility) {
			SidebarPane(
				model: shellModel,
				selection: selectedWorkspaceID,
				requestDeleteWorkspace: { workspaceID in
					sceneContext.requestDeleteWorkspaceConfirmation(workspaceID)
				}
			)
				.navigationSplitViewColumnWidth(sidebarColumnWidth)
		} detail: {
			ContentPane(model: shellModel, selectedWorkspaceID: selectedWorkspaceID)
				.navigationSplitViewColumnWidth(min: 640, ideal: contentColumnIdealWidth)
		}
		.inspector(isPresented: $bindableSceneContext.isInspectorVisible) {
			DetailPane(model: shellModel, selectedWorkspaceID: selectedWorkspaceID)
				.inspectorColumnWidth(
					min: inspectorColumnMinimumWidth,
					ideal: inspectorColumnIdealWidth,
					max: inspectorColumnMaximumWidth
				)
		}
		.windowRole(.mainShell)
		.windowCloseConfirmation(
			requiresConfirmation: shellModel.requiresLastPaneCloseConfirmation,
			isBypassingConfirmation: $bindableSceneContext.isBypassingLastPaneCloseConfirmation
		)
		.sheet(isPresented: $bindableSceneContext.isSavedWorkspaceLibraryPresented) {
			SavedWorkspaceLibrarySheet(
				model: shellModel,
				selectedWorkspaceID: selectedWorkspaceID,
				isPresented: $bindableSceneContext.isSavedWorkspaceLibraryPresented
			)
		}
		.alert(
			"Delete Workspace?",
			isPresented: deleteWorkspaceAlertBinding,
			presenting: sceneContext.workspacePendingDeletion
		) { _ in
			Button("Delete", role: .destructive) {
				sceneContext.confirmWorkspaceDeletion()
			}
			.accessibilityIdentifier("sidebar.deleteWorkspaceConfirmButton")

			Button("Cancel", role: .cancel) {
				sceneContext.cancelWorkspaceDeletion()
			}
			.accessibilityIdentifier("sidebar.deleteWorkspaceCancelButton")
		} message: { workspace in
			Text("Delete “\(workspace.title)” and close every pane in it? Your other workspaces stay open.")
		}
		.focusedSceneValue(\.mainShellSceneContext, sceneContext)
		.focusedSceneValue(\.mainShellSceneCommandState, sceneContext.commandState)
		.toolbar {
			ToolbarItem(placement: .navigation) {
				Button {
					sceneContext.openSavedWorkspaceLibrary()
				} label: {
					Label("Open Saved Workspaces", systemImage: "folder")
				}
				.labelStyle(.iconOnly)
				.help("Open saved workspaces (\u{2318}O)")
				.accessibilityIdentifier("mainShell.openSavedWorkspacesButton")
			}

			ToolbarItem(placement: .navigation) {
				Button {
					sceneContext.createWorkspace()
				} label: {
					Label("New Workspace", systemImage: "plus.rectangle.on.rectangle")
				}
				.labelStyle(.iconOnly)
				.help("Create a new workspace (\u{2318}N)")
				.accessibilityIdentifier("mainShell.newWorkspaceButton")
			}

			ToolbarItemGroup(placement: .primaryAction) {
				Button {
					sceneContext.splitFocusedPane(.right)
				} label: {
					Label("Split Right", systemImage: "uiwindow.split.2x1")
				}
				.labelStyle(.iconOnly)
				.help("Split the focused pane to the right (\u{2318}D)")
				.disabled(!sceneContext.canSplitFocusedPane)
				.accessibilityIdentifier("mainShell.splitRightButton")

				Button {
					sceneContext.splitFocusedPane(.down)
				} label: {
					Label("Split Down", systemImage: "uiwindow.split.2x1.rotate.90")
				}
				.labelStyle(.iconOnly)
				.help("Split the focused pane downward (\u{21E7}\u{2318}D)")
				.disabled(!sceneContext.canSplitFocusedPane)
				.accessibilityIdentifier("mainShell.splitDownButton")
			}

			ToolbarItem(placement: .primaryAction) {
				Button {
					sceneContext.toggleInspector()
				} label: {
					Label(
						sceneContext.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
						systemImage: "sidebar.right"
					)
				}
				.labelStyle(.iconOnly)
				.help(sceneContext.isInspectorVisible ? "Hide the inspector (\u{21E7}\u{2318}B)" : "Show the inspector (\u{21E7}\u{2318}B)")
				.accessibilityIdentifier("mainShell.toggleInspectorButton")
			}
		}
		.task {
			applySceneStateIfNeeded()
		}
		.onChange(of: sceneContext.selectedWorkspaceID?.rawValue.uuidString) { _, newValue in
			restoredSelectedWorkspaceID = newValue
		}
		.onChange(of: shellModel.workspaces.map(\.id.rawValue)) { _, _ in
			sceneContext.normalizeSelectionAfterWorkspaceMutation()
		}
		.onChange(of: sceneContext.isInspectorVisible) { _, newValue in
			restoredInspectorVisible = newValue
		}
		.onChange(of: sceneContext.isSidebarVisible) { _, newValue in
			restoredSidebarVisible = newValue
		}
	}

	private var selectedWorkspaceID: Binding<WorkspaceID?> {
		Binding(
			get: { sceneContext.selectedWorkspaceID },
			set: { newValue in
				sceneContext.selectedWorkspaceID = shellModel.normalizedWorkspaceSelection(newValue)
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
		sceneContext.applyRestoredSceneState(
			restoredSelectedWorkspaceID: restoredSelection,
			isSidebarVisible: restoredSidebarVisible,
			isInspectorVisible: restoredInspectorVisible
		)
	}

	private var deleteWorkspaceAlertBinding: Binding<Bool> {
		Binding(
			get: { sceneContext.workspacePendingDeletion != nil },
			set: { isPresented in
				if !isPresented {
					sceneContext.cancelWorkspaceDeletion()
				}
			}
		)
	}
}
