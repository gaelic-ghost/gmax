//
//  ShellModel.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import Combine
import OSLog
import SwiftUI

@MainActor
final class ShellModel: ObservableObject {
	@Published var workspaces: [Workspace]
	@Published var columnVisibility: NavigationSplitViewVisibility
	@Published var isInspectorVisible: Bool
	@Published var recentlyClosedWorkspaceCount = 0

	let persistence: ShellPersistenceController
	let launchContextBuilder: TerminalLaunchContextBuilder
	let sessions: TerminalSessionRegistry
	let paneControllers: TerminalPaneControllerStore
	var currentWorkspaceID: WorkspaceID?
	var paneFramesByWorkspace: [WorkspaceID: [PaneID: CGRect]]
	var paneFocusHistoryByWorkspace: [WorkspaceID: [PaneID]]
	var pendingPersistenceTask: Task<Void, Never>?
	var recentlyClosedWorkspaces: [RecentlyClosedWorkspace] = []
	let appLogger = Logger.gmax(.app)
	let diagnosticsLogger = Logger.gmax(.diagnostics)
	let workspaceLogger = Logger.gmax(.workspace)
	let paneLogger = Logger.gmax(.pane)

	init() {
		WorkspacePersistenceDefaults.registerDefaults()
		let persistence = ShellPersistenceController.shared
		let shouldRestorePersistedWorkspaces = UserDefaults.standard.bool(
			forKey: WorkspacePersistenceDefaults.restoreWorkspacesOnLaunchKey
		)
		let persistedWorkspaces = shouldRestorePersistedWorkspaces ? persistence.loadWorkspaces() : []
		let workspaces = persistedWorkspaces.isEmpty ? [Self.makeDefaultWorkspace()] : persistedWorkspaces
		let launchContextBuilder = TerminalLaunchContextBuilder.live()
		self.persistence = persistence
		self.launchContextBuilder = launchContextBuilder
		self.sessions = TerminalSessionRegistry(
			workspaces: workspaces,
			defaultLaunchConfiguration: launchContextBuilder.makeLaunchConfiguration()
		)
		self.paneControllers = TerminalPaneControllerStore()
		self.workspaces = workspaces
		self.currentWorkspaceID = workspaces.first?.id
		self.columnVisibility = .all
		self.isInspectorVisible = true
		self.paneFramesByWorkspace = [:]
		self.paneFocusHistoryByWorkspace = Self.initialFocusHistory(for: workspaces)
		if shouldRestorePersistedWorkspaces, !persistedWorkspaces.isEmpty {
			appLogger.notice("Restored persisted workspaces during app launch. Restored workspace count: \(persistedWorkspaces.count)")
		} else if shouldRestorePersistedWorkspaces {
			appLogger.notice("Workspace restoration is enabled for launch, but there were no persisted workspaces to restore. The app started with the default workspace instead.")
		} else {
			appLogger.notice("Workspace restoration on launch is disabled, so the app started with the default workspace state for this session.")
		}
	}

	convenience init(
		workspaces: [Workspace],
		selectedWorkspaceID: WorkspaceID?,
		columnVisibility: NavigationSplitViewVisibility = .all,
		isInspectorVisible: Bool = true
	) {
		self.init(
			workspaces: workspaces,
			selectedWorkspaceID: selectedWorkspaceID,
			persistence: .shared,
			launchContextBuilder: .live(),
			columnVisibility: columnVisibility,
			isInspectorVisible: isInspectorVisible
		)
	}

	init(
		workspaces: [Workspace],
		selectedWorkspaceID: WorkspaceID?,
		persistence: ShellPersistenceController,
		launchContextBuilder: TerminalLaunchContextBuilder,
		columnVisibility: NavigationSplitViewVisibility = .all,
		isInspectorVisible: Bool = true
	) {
		self.persistence = persistence
		self.launchContextBuilder = launchContextBuilder
		self.sessions = TerminalSessionRegistry(
			workspaces: workspaces,
			defaultLaunchConfiguration: launchContextBuilder.makeLaunchConfiguration()
		)
		self.paneControllers = TerminalPaneControllerStore()
		self.workspaces = workspaces
		self.currentWorkspaceID = selectedWorkspaceID
		self.columnVisibility = columnVisibility
		self.isInspectorVisible = isInspectorVisible
		self.paneFramesByWorkspace = [:]
		self.paneFocusHistoryByWorkspace = Self.initialFocusHistory(for: workspaces)
	}

	var selectedWorkspaceIndex: Int? {
		guard let currentWorkspaceID else {
			return nil
		}
		return workspaces.firstIndex { $0.id == currentWorkspaceID }
	}

	var selectedWorkspace: Workspace? {
		guard let selectedWorkspaceIndex else {
			return nil
		}
		return workspaces[selectedWorkspaceIndex]
	}

	var focusedPane: PaneLeaf? {
		guard
			let workspace = selectedWorkspace,
			let root = workspace.root,
			let focusedPaneID = workspace.focusedPaneID
		else {
			return nil
		}
		return root.findPane(id: focusedPaneID)
	}

	var requiresLastPaneCloseConfirmation: Bool {
		guard let workspace = workspaces.first, workspaces.count == 1 else {
			return false
		}
		return workspace.paneCount == 1
	}

	func setCurrentWorkspaceID(_ workspaceID: WorkspaceID?) {
		currentWorkspaceID = normalizedWorkspaceSelection(workspaceID)
	}

	func normalizedWorkspaceSelection(_ workspaceID: WorkspaceID?) -> WorkspaceID? {
		if let workspaceID, workspaces.contains(where: { $0.id == workspaceID }) {
			return workspaceID
		}
		return workspaces.first?.id
	}

	func workspace(for workspaceID: WorkspaceID) -> Workspace? {
		workspaces.first { $0.id == workspaceID }
	}

	func focusedPane(in workspaceID: WorkspaceID) -> PaneLeaf? {
		guard
			let workspace = workspace(for: workspaceID),
			let root = workspace.root,
			let focusedPaneID = workspace.focusedPaneID
		else {
			return nil
		}

		return root.findPane(id: focusedPaneID)
	}

	func toggleSidebar() {
		columnVisibility = columnVisibility == .all ? .doubleColumn : .all
		let resolvedColumnVisibility = String(describing: columnVisibility)
		diagnosticsLogger.notice("Toggled sidebar visibility. New split-view column visibility: \(resolvedColumnVisibility, privacy: .public)")
	}

	func toggleInspector() {
		isInspectorVisible.toggle()
		let inspectorVisibilityDescription = isInspectorVisible ? "visible" : "hidden"
		diagnosticsLogger.notice("Toggled inspector visibility. Inspector is now \(inspectorVisibilityDescription, privacy: .public).")
	}

	func setInspectorVisible(_ isVisible: Bool) {
		isInspectorVisible = isVisible
		diagnosticsLogger.notice("Set inspector visibility from scene or command state restoration. Inspector is now \(isVisible ? "visible" : "hidden", privacy: .public).")
	}

	func controller(for pane: PaneLeaf) -> TerminalPaneController {
		let session = sessions.ensureSession(id: pane.sessionID)
		return paneControllers.controller(for: pane, session: session)
	}
}
