import Foundation
import OSLog
import SwiftUI

// MARK: - Workspace Lifecycle
// MARK: Workspace creation, duplication, close, restore, and library persistence flows.

extension WorkspaceStore {
	@discardableResult
	func createWorkspace() -> WorkspaceID {
		let pane = PaneLeaf()
		let workspace = Workspace(
			title: uniqueWorkspaceTitle(startingWith: "Workspace \(workspaces.count + 1)"),
			root: .leaf(pane)
		)

		workspaces.append(workspace)
		_ = sessions.ensureSession(
			id: pane.sessionID,
			launchConfiguration: launchContextBuilder.makeLaunchConfiguration()
		)
		Logger.workspace.notice("Created a new workspace and seeded it with an initial pane. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
		schedulePersistenceSave()
		return workspace.id
	}

	func renameWorkspace(_ workspaceID: WorkspaceID, to proposedTitle: String) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}

		let trimmedTitle = proposedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmedTitle.isEmpty else {
			return
		}

		let previousTitle = workspaces[workspaceIndex].title
		workspaces[workspaceIndex].title = trimmedTitle
		Logger.workspace.notice("Renamed a workspace. Previous title: \(previousTitle, privacy: .public). New title: \(trimmedTitle, privacy: .public). Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
		schedulePersistenceSave()
	}

	@discardableResult
	func duplicateWorkspace(_ workspaceID: WorkspaceID) -> WorkspaceID? {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return nil
		}

		let workspace = workspaces[workspaceIndex]
		let duplicatedWorkspace = Workspace(
			title: uniqueWorkspaceTitle(startingWith: "\(workspace.title) Copy"),
			root: workspace.root.map { duplicateNode($0) }
		)
		workspaces.insert(duplicatedWorkspace, at: workspaceIndex + 1)
		Logger.workspace.notice("Duplicated a workspace layout into a new workspace. Source workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). New workspace title: \(duplicatedWorkspace.title, privacy: .public). New workspace ID: \(duplicatedWorkspace.id.rawValue.uuidString, privacy: .public)")
		schedulePersistenceSave()
		return duplicatedWorkspace.id
	}

	func closeWorkspace(_ workspaceID: WorkspaceID) -> WorkspaceID? {
		removeWorkspace(
			workspaceID,
			recordRecentlyClosed: UserDefaults.standard.bool(
				forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey
			),
			saveToLibrary: UserDefaults.standard.bool(
				forKey: WorkspacePersistenceDefaults.autoSaveClosedWorkspacesKey
			)
		)
	}

	func deleteWorkspace(_ workspaceID: WorkspaceID) {
		guard workspaces.count > 1, workspaces.contains(where: { $0.id == workspaceID }) else {
			return
		}

		_ = removeWorkspace(
			workspaceID,
			recordRecentlyClosed: false,
			saveToLibrary: false
		)
	}

	@discardableResult
	func undoCloseWorkspace() -> WorkspaceID? {
		guard let closedWorkspace = recentlyClosedWorkspaces.popLast() else {
			return nil
		}

		let insertionIndex = min(closedWorkspace.formerIndex, workspaces.count)
		workspaces.insert(closedWorkspace.workspace, at: insertionIndex)

		for leaf in closedWorkspace.workspace.root?.leaves() ?? [] {
			let launchConfiguration = closedWorkspace.launchConfigurationsBySessionID[leaf.sessionID]
				?? launchContextBuilder.makeLaunchConfiguration()
			let session = sessions.ensureSession(id: leaf.sessionID, launchConfiguration: launchConfiguration)
			session.title = closedWorkspace.titlesBySessionID[leaf.sessionID] ?? session.title
			session.currentDirectory = launchConfiguration.currentDirectory
			session.setRestoredTranscript(closedWorkspace.transcriptsBySessionID[leaf.sessionID])
		}

		recentlyClosedWorkspaceCount = recentlyClosedWorkspaces.count
		Logger.workspace.notice("Reopened a recently closed workspace from the in-memory history stack. Workspace title: \(closedWorkspace.workspace.title, privacy: .public). Workspace ID: \(closedWorkspace.workspace.id.rawValue.uuidString, privacy: .public)")
		schedulePersistenceSave()
		return closedWorkspace.workspace.id
	}

	func clearRecentlyClosedWorkspaces() {
		recentlyClosedWorkspaces.removeAll()
		recentlyClosedWorkspaceCount = 0
		Logger.workspace.notice("Cleared the in-memory recently closed workspace stack for the current app session.")
	}

	@discardableResult
	func saveWorkspaceToLibrary(
		_ workspaceID: WorkspaceID,
		transcriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> SavedWorkspaceListing? {
		guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
			Logger.workspace.error("The app was asked to save a workspace to the library, but that workspace no longer exists in the current shell model. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
			return nil
		}

		let resolvedTranscripts = captureWorkspaceTranscripts(
			for: workspace,
			explicitTranscriptsBySessionID: transcriptsBySessionID
		)

		let summary = persistence.saveWorkspaceToLibrary(
			from: workspace,
			sessions: sessions,
			transcriptsBySessionID: resolvedTranscripts
		)
		if let summary {
			Logger.workspace.notice("Saved a workspace to the library. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public). Saved workspace ID: \(summary.id.rawValue.uuidString, privacy: .public)")
		}
		return summary
	}

	func listSavedWorkspaces(matching query: String? = nil) -> [SavedWorkspaceListing] {
		persistence.listSavedWorkspaces(matching: query)
	}

	@discardableResult
	func closeWorkspaceToLibrary(
		_ workspaceID: WorkspaceID,
		transcriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> WorkspaceID? {
		return removeWorkspace(
			workspaceID,
			recordRecentlyClosed: UserDefaults.standard.bool(
				forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey
			),
			saveToLibrary: true,
			explicitTranscriptsBySessionID: transcriptsBySessionID
		)
	}

	@discardableResult
	func openSavedWorkspace(_ savedWorkspaceID: SavedWorkspaceID) -> WorkspaceID? {
		guard let savedWorkspace = persistence.loadSavedWorkspace(id: savedWorkspaceID) else {
			Logger.workspace.error("The app could not reopen a saved workspace because the requested library entry was missing or unreadable. Check the persistence logs for the exact load failure. Saved workspace ID: \(savedWorkspaceID.rawValue.uuidString, privacy: .public)")
			return nil
		}

		var launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration] = [:]
		var transcriptsBySessionID: [TerminalSessionID: String] = [:]
		var titlesBySessionID: [TerminalSessionID: String] = [:]
		let restoredWorkspace = Workspace(
			title: {
					let title = savedWorkspace.title.trimmingCharacters(in: .whitespacesAndNewlines)
				let baseTitle = title.isEmpty ? "Workspace" : title
				return uniqueWorkspaceTitle(
					startingWith: workspaces.map(\.title).contains(baseTitle)
						? "\(baseTitle) (Opened \(Date.now.formatted(date: .omitted, time: .shortened)))"
						: baseTitle
				)
			}(),
				root: savedWorkspace.workspace.root.map {
					restoreNode(
						$0,
						paneSnapshotsBySessionID: savedWorkspace.paneSnapshotsBySessionID,
						launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
						transcriptsBySessionID: &transcriptsBySessionID,
						titlesBySessionID: &titlesBySessionID
					)
				},
				savedWorkspaceID: savedWorkspace.savedWorkspaceID
			)
		workspaces.append(restoredWorkspace)

		for (sessionID, launchConfiguration) in launchConfigurationsBySessionID {
			let session = sessions.ensureSession(id: sessionID, launchConfiguration: launchConfiguration)
			session.title = titlesBySessionID[sessionID] ?? "Shell"
			session.currentDirectory = launchConfiguration.currentDirectory
			session.setRestoredTranscript(transcriptsBySessionID[sessionID])
		}

		persistence.markSavedWorkspaceOpened(savedWorkspaceID)
		Logger.workspace.notice("Opened a workspace from the saved-workspace library. Saved workspace title: \(savedWorkspace.title, privacy: .public). Saved workspace ID: \(savedWorkspaceID.rawValue.uuidString, privacy: .public). Restored pane count: \((restoredWorkspace.root?.leaves().count ?? 0))")
		schedulePersistenceSave()
		return restoredWorkspace.id
	}

	func deleteSavedWorkspace(_ savedWorkspaceID: SavedWorkspaceID) {
		guard persistence.deleteSavedWorkspace(id: savedWorkspaceID) else {
			Logger.workspace.error("The app could not delete a saved workspace from the library because persistence did not confirm the deletion. Check the persistence logs for the exact failure. Saved workspace ID: \(savedWorkspaceID.rawValue.uuidString, privacy: .public)")
			return
		}

		Logger.workspace.notice("Deleted a saved workspace from the library. Saved workspace ID: \(savedWorkspaceID.rawValue.uuidString, privacy: .public)")
	}

}

// MARK: - Workspace Helpers
// MARK: Internal helpers that support workspace cloning, restore, close, and persistence workflows.

extension WorkspaceStore {
	struct RecentlyClosedWorkspace {
		let workspace: Workspace
		let formerIndex: Int
		let launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration]
		let titlesBySessionID: [TerminalSessionID: String]
		let transcriptsBySessionID: [TerminalSessionID: String]
	}

	private func uniqueWorkspaceTitle(startingWith baseTitle: String) -> String {
		let normalizedBaseTitle = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
		let resolvedBaseTitle = normalizedBaseTitle.isEmpty ? "Workspace" : normalizedBaseTitle
		let existingTitles = Set(workspaces.map(\.title))
		guard existingTitles.contains(resolvedBaseTitle) else {
			return resolvedBaseTitle
		}

		var suffix = 2
		while true {
			let candidate = "\(resolvedBaseTitle) \(suffix)"
			if !existingTitles.contains(candidate) {
				return candidate
			}
			suffix += 1
		}
	}

	private func duplicateNode(_ node: PaneNode) -> PaneNode {
		switch node {
			case .leaf(let leaf):
				let sourceSession = sessions.ensureSession(id: leaf.sessionID)
				let inheritedCurrentDirectory = sourceSession.currentDirectory
					?? sourceSession.launchConfiguration.currentDirectory
				let clonedLeaf = PaneLeaf()
				_ = sessions.ensureSession(
					id: clonedLeaf.sessionID,
					launchConfiguration: launchContextBuilder.makeLaunchConfiguration(
						currentDirectory: inheritedCurrentDirectory
					)
				)
				return .leaf(clonedLeaf)

			case .split(let split):
				return .split(
					PaneSplit(
						axis: split.axis,
						fraction: split.fraction,
						first: duplicateNode(split.first),
						second: duplicateNode(split.second)
					)
				)
		}
	}

	func schedulePersistenceSave() {
		pendingPersistenceTask?.cancel()
		let workspacesSnapshot = workspaces
		let recentlyClosedSnapshot = recentlyClosedWorkspaces.map { workspace in
			RecentlyClosedWorkspaceStateInput(
				workspace: workspace.workspace,
				formerIndex: workspace.formerIndex,
				launchConfigurationsBySessionID: workspace.launchConfigurationsBySessionID,
				titlesBySessionID: workspace.titlesBySessionID,
				transcriptsBySessionID: workspace.transcriptsBySessionID
			)
		}
		let transcriptsByWorkspaceID = Dictionary(
			uniqueKeysWithValues: workspacesSnapshot.map { workspace in
				(
					workspace.id,
						captureWorkspaceTranscripts(
						for: workspace,
						explicitTranscriptsBySessionID: [:]
					)
				)
			}
		)
		pendingPersistenceTask = Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(250))
			guard !Task.isCancelled else {
				return
			}
			persistence.saveSceneState(
				for: sceneIdentity,
				liveWorkspaces: workspacesSnapshot,
				recentlyClosedWorkspaces: recentlyClosedSnapshot,
				sessions: sessions,
				liveTranscriptsByWorkspaceID: transcriptsByWorkspaceID
			)
		}
	}

	@discardableResult
	func removeWorkspace(
		_ workspaceID: WorkspaceID,
		recordRecentlyClosed: Bool,
		saveToLibrary: Bool,
		explicitTranscriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> WorkspaceID? {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return nil
		}

		let workspace = workspaces[workspaceIndex]
		if saveToLibrary {
				let resolvedTranscripts = captureWorkspaceTranscripts(
				for: workspace,
				explicitTranscriptsBySessionID: explicitTranscriptsBySessionID
			)
			_ = persistence.saveWorkspaceToLibrary(
				from: workspace,
				sessions: sessions,
				transcriptsBySessionID: resolvedTranscripts
			)
		}

		if recordRecentlyClosed {
			recordRecentlyClosedWorkspace(workspace, formerIndex: workspaceIndex)
		}

		workspaces.remove(at: workspaceIndex)
		removeUnreferencedSessions()

		let nextSelectedWorkspaceID = workspaces.isEmpty ? nil : workspaces[min(workspaceIndex, workspaces.count - 1)].id

		Logger.workspace.notice("Closed a workspace from the live shell. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public). Recorded in recently closed: \(recordRecentlyClosed). Saved to library: \(saveToLibrary)")
		schedulePersistenceSave()
		return nextSelectedWorkspaceID
	}

	private func recordRecentlyClosedWorkspace(_ workspace: Workspace, formerIndex: Int) {
		guard UserDefaults.standard.bool(forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey) else {
			return
		}

		let launchConfigurationsBySessionID = Dictionary(uniqueKeysWithValues: (workspace.root?.leaves() ?? []).map { leaf in
			let session = sessions.ensureSession(id: leaf.sessionID)
			let currentDirectory = session.currentDirectory ?? session.launchConfiguration.currentDirectory
			let launchConfiguration = launchContextBuilder.makeLaunchConfiguration(
				currentDirectory: currentDirectory
			)
			return (leaf.sessionID, launchConfiguration)
		})
		let titlesBySessionID = Dictionary(uniqueKeysWithValues: (workspace.root?.leaves() ?? []).map { leaf in
			let session = sessions.ensureSession(id: leaf.sessionID)
			return (leaf.sessionID, session.title)
		})
			let transcriptsBySessionID = captureWorkspaceTranscripts(
			for: workspace,
			explicitTranscriptsBySessionID: [:]
		)

		recentlyClosedWorkspaces.removeAll { $0.workspace.id == workspace.id }
		recentlyClosedWorkspaces.append(
			RecentlyClosedWorkspace(
				workspace: workspace,
				formerIndex: formerIndex,
				launchConfigurationsBySessionID: launchConfigurationsBySessionID,
				titlesBySessionID: titlesBySessionID,
				transcriptsBySessionID: transcriptsBySessionID
			)
		)
		if recentlyClosedWorkspaces.count > WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount {
			recentlyClosedWorkspaces.removeFirst(
				recentlyClosedWorkspaces.count - WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount
			)
		}
		recentlyClosedWorkspaceCount = recentlyClosedWorkspaces.count
	}

		private func captureWorkspaceTranscripts(
		for workspace: Workspace,
		explicitTranscriptsBySessionID: [TerminalSessionID: String]
	) -> [TerminalSessionID: String] {
		var resolvedTranscripts = explicitTranscriptsBySessionID

		for leaf in workspace.root?.leaves() ?? [] where resolvedTranscripts[leaf.sessionID] == nil {
			guard let transcript = paneControllers.existingController(for: leaf.id)?.captureTranscript() else {
				continue
			}
			resolvedTranscripts[leaf.sessionID] = transcript
		}

		return resolvedTranscripts
	}
	private func restoreNode(
		_ node: PaneNode,
		paneSnapshotsBySessionID: [TerminalSessionID: WorkspaceSessionSnapshot],
		launchConfigurationsBySessionID: inout [TerminalSessionID: TerminalLaunchConfiguration],
		transcriptsBySessionID: inout [TerminalSessionID: String],
		titlesBySessionID: inout [TerminalSessionID: String]
	) -> PaneNode {
		switch node {
			case .leaf(let leaf):
				let restoredLeaf = PaneLeaf()
				let paneSnapshot = paneSnapshotsBySessionID[leaf.sessionID]
				let launchConfiguration = paneSnapshot?.launchConfiguration
					?? launchContextBuilder.makeLaunchConfiguration()
				launchConfigurationsBySessionID[restoredLeaf.sessionID] = launchConfiguration
				if let transcript = paneSnapshot?.transcript {
					transcriptsBySessionID[restoredLeaf.sessionID] = transcript
				}
				if let title = paneSnapshot?.title {
					titlesBySessionID[restoredLeaf.sessionID] = title
				}
				return .leaf(restoredLeaf)

			case .split(let split):
				return .split(
					PaneSplit(
						axis: split.axis,
						fraction: split.fraction,
						first: restoreNode(
							split.first,
							paneSnapshotsBySessionID: paneSnapshotsBySessionID,
							launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
							transcriptsBySessionID: &transcriptsBySessionID,
							titlesBySessionID: &titlesBySessionID
						),
						second: restoreNode(
							split.second,
							paneSnapshotsBySessionID: paneSnapshotsBySessionID,
							launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
							transcriptsBySessionID: &transcriptsBySessionID,
							titlesBySessionID: &titlesBySessionID
						)
					)
				)
		}
	}
}
