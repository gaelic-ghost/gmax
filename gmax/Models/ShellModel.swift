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
	let appLogger = Logger.gmax(.app)
	let diagnosticsLogger = Logger.gmax(.diagnostics)
	let workspaceLogger = Logger.gmax(.workspace)
	let paneLogger = Logger.gmax(.pane)

	init(
		workspaces: [Workspace]? = nil,
		persistence: ShellPersistenceController? = nil,
		launchContextBuilder: TerminalLaunchContextBuilder? = nil
	) {
		WorkspacePersistenceDefaults.registerDefaults()
		let persistence = persistence ?? .shared
		let launchContextBuilder = launchContextBuilder ?? .live()
		let resolvedWorkspaces: [Workspace]
		let launchRestoreLog: (message: String, restoredCount: Int?)?

		if let workspaces {
			resolvedWorkspaces = workspaces
			launchRestoreLog = nil
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
				launchRestoreLog = (
					"Restored persisted workspaces during app launch.",
					persistedWorkspaces.count
				)
			} else if shouldRestorePersistedWorkspaces {
				launchRestoreLog = (
					"Workspace restoration is enabled for launch, but there were no persisted workspaces to restore. The app started with the default workspace instead.",
					nil
				)
			} else {
				launchRestoreLog = (
					"Workspace restoration on launch is disabled, so the app started with the default workspace state for this session.",
					nil
				)
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

		if let launchRestoreLog {
			if let restoredCount = launchRestoreLog.restoredCount {
				appLogger.notice("\(launchRestoreLog.message) Restored workspace count: \(restoredCount)")
			} else {
				appLogger.notice("\(launchRestoreLog.message)")
			}
		}
	}
}
