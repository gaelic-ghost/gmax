//
//  MainShellSceneView.swift
//  gmax
//
//  Created by Codex on 4/14/26.
//

import OSLog
import SwiftUI

struct MainShellSceneView: View {
	@ObservedObject var shellModel: ShellModel
	@Binding var selectedWorkspaceID: WorkspaceID?
	@Binding var isBypassingLastPaneCloseConfirmation: Bool
	@Binding var isSavedWorkspaceLibraryPresented: Bool
	@SceneStorage("mainShell.selectedWorkspaceID") private var restoredSelectedWorkspaceID: String?
	@SceneStorage("mainShell.isInspectorVisible") private var restoredInspectorVisible = true
	@State private var hasAppliedSceneState = false
	private let appLogger = Logger.gmax(.app)

	private let sidebarColumnWidth: CGFloat = 220
	private let contentColumnIdealWidth: CGFloat = 920
	private let detailColumnMinimumWidth: CGFloat = 220
	private let detailColumnIdealWidth: CGFloat = 260
	private let detailColumnMaximumWidth: CGFloat = 340

	var body: some View {
		NavigationSplitView(columnVisibility: $shellModel.columnVisibility) {
			SidebarPane(model: shellModel, selection: $selectedWorkspaceID)
				.navigationSplitViewColumnWidth(sidebarColumnWidth)
		} content: {
			ContentPane(model: shellModel, selectedWorkspaceID: $selectedWorkspaceID)
				.navigationSplitViewColumnWidth(min: 640, ideal: contentColumnIdealWidth)
		} detail: {
			if shellModel.isInspectorVisible {
				DetailPane(model: shellModel, selectedWorkspaceID: $selectedWorkspaceID)
					.navigationSplitViewColumnWidth(
						min: detailColumnMinimumWidth,
						ideal: detailColumnIdealWidth,
						max: detailColumnMaximumWidth
					)
			} else {
				Color.clear
					.navigationSplitViewColumnWidth(0)
			}
		}
		.windowRole(.mainShell)
		.windowCloseConfirmation(
			requiresConfirmation: shellModel.requiresLastPaneCloseConfirmation,
			isBypassingConfirmation: $isBypassingLastPaneCloseConfirmation
		)
		.sheet(isPresented: $isSavedWorkspaceLibraryPresented) {
			SavedWorkspaceLibrarySheet(
				model: shellModel,
				selectedWorkspaceID: $selectedWorkspaceID,
				isPresented: $isSavedWorkspaceLibraryPresented
			)
		}
		.toolbar {
			ToolbarItem(placement: .navigation) {
				Button {
					selectedWorkspaceID = shellModel.createWorkspace()
				} label: {
					Label("New Workspace", systemImage: "plus.rectangle.on.rectangle")
				}
			}

			ToolbarItem(placement: .automatic) {
				Button {
					isSavedWorkspaceLibraryPresented = true
				} label: {
					Label("Open Saved Workspaces", systemImage: "folder")
				}
				.help("Open saved workspaces (\u{2318}O)")
			}

			ToolbarItem(placement: .automatic) {
				Button {
					if let workspaceID = selectedWorkspaceID {
						selectedWorkspaceID = shellModel.createPane(in: workspaceID)
					} else {
						selectedWorkspaceID = shellModel.createWorkspace()
					}
				} label: {
					Label("New Pane", systemImage: "uiwindow.split.2x1")
				}
			}

			ToolbarItem(placement: .automatic) {
				Button {
					shellModel.toggleInspector()
				} label: {
					Label(
						shellModel.isInspectorVisible ? "Hide Inspector" : "Show Inspector",
						systemImage: "sidebar.right"
					)
				}
			}
		}
		.task {
			applySceneStateIfNeeded()
		}
		.onChange(of: selectedWorkspaceID?.rawValue.uuidString) { _, newValue in
			restoredSelectedWorkspaceID = newValue
			shellModel.setCurrentWorkspaceID(selectedWorkspaceID)
		}
		.onChange(of: shellModel.workspaces.map(\.id.rawValue)) { _, _ in
			let normalizedSelection = shellModel.normalizedWorkspaceSelection(selectedWorkspaceID)
			if normalizedSelection != selectedWorkspaceID {
				selectedWorkspaceID = normalizedSelection
			}
			shellModel.setCurrentWorkspaceID(normalizedSelection)
		}
		.onChange(of: shellModel.isInspectorVisible) { _, newValue in
			restoredInspectorVisible = newValue
		}
	}

	private func applySceneStateIfNeeded() {
		guard !hasAppliedSceneState else {
			return
		}

		hasAppliedSceneState = true
		shellModel.setInspectorVisible(restoredInspectorVisible)

		let restoredSelection = restoredSelectedWorkspaceID
			.flatMap(UUID.init(uuidString:))
			.map { WorkspaceID(rawValue: $0) }
		let normalizedSelection = shellModel.normalizedWorkspaceSelection(restoredSelection ?? selectedWorkspaceID)
		appLogger.notice("Applied per-scene shell state restoration. Restored workspace selection: \(restoredSelection?.rawValue.uuidString ?? "(none)", privacy: .public). Normalized workspace selection: \(normalizedSelection?.rawValue.uuidString ?? "(none)", privacy: .public). Restored inspector visibility: \(restoredInspectorVisible ? "visible" : "hidden", privacy: .public)")
		selectedWorkspaceID = normalizedSelection
		shellModel.setCurrentWorkspaceID(normalizedSelection)
	}
}
