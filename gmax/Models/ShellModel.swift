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
	@Published var recentlyClosedWorkspaceCount = 0

	let persistence: ShellPersistenceController
	let launchContextBuilder: TerminalLaunchContextBuilder
	let sessions: TerminalSessionRegistry
	let paneControllers: TerminalPaneControllerStore
	var paneFramesByWorkspace: [WorkspaceID: [PaneID: CGRect]]
	var paneFocusHistoryByWorkspace: [WorkspaceID: [PaneID]]
	var pendingPersistenceTask: Task<Void, Never>?
	var recentlyClosedWorkspaces: [RecentlyClosedWorkspace] = []

	init(
		workspaces: [Workspace]? = nil,
		persistence: ShellPersistenceController? = nil,
		launchContextBuilder: TerminalLaunchContextBuilder? = nil
	) {
		UserDefaults.standard.register(
			defaults: [
				WorkspacePersistenceDefaults.restoreWorkspacesOnLaunchKey:
					WorkspacePersistenceDefaults.systemRestoresWindowsByDefault(),
				WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey: true,
				WorkspacePersistenceDefaults.autoSaveClosedWorkspacesKey: false
			]
		)
		let persistence = persistence ?? .shared
		let launchContextBuilder = launchContextBuilder ?? .live()
		let resolvedWorkspaces: [Workspace]

		if let workspaces {
			resolvedWorkspaces = workspaces
		} else {
			let shouldRestorePersistedWorkspaces = UserDefaults.standard.bool(
				forKey: WorkspacePersistenceDefaults.restoreWorkspacesOnLaunchKey
			)
			let persistedWorkspaces = shouldRestorePersistedWorkspaces ? persistence.loadWorkspaces() : []
			if persistedWorkspaces.isEmpty {
				let pane = PaneLeaf()
				resolvedWorkspaces = [Workspace(title: "Workspace 1", root: .leaf(pane), focusedPaneID: pane.id)]
			} else {
				resolvedWorkspaces = persistedWorkspaces
			}

			if shouldRestorePersistedWorkspaces, !persistedWorkspaces.isEmpty {
				Logger.app.notice("Restored persisted workspaces during app launch. Restored workspace count: \(persistedWorkspaces.count)")
			} else if shouldRestorePersistedWorkspaces {
				Logger.app.notice("Workspace restoration is enabled for launch, but there were no persisted workspaces to restore. The app started with the default workspace instead.")
			} else {
				Logger.app.notice("Workspace restoration on launch is disabled, so the app started with the default workspace state for this session.")
			}
		}

		self.persistence = persistence
		self.launchContextBuilder = launchContextBuilder
		self.sessions = TerminalSessionRegistry(
			workspaces: resolvedWorkspaces,
			defaultLaunchConfiguration: launchContextBuilder.makeLaunchConfiguration()
		)
		self.paneControllers = TerminalPaneControllerStore()
		self.workspaces = resolvedWorkspaces
		self.paneFramesByWorkspace = [:]
		self.paneFocusHistoryByWorkspace = Dictionary(
			uniqueKeysWithValues: resolvedWorkspaces.compactMap { workspace in
				guard let focusedPaneID = workspace.focusedPaneID else {
					return nil
				}
				return (workspace.id, [focusedPaneID])
			}
		)
	}
}
