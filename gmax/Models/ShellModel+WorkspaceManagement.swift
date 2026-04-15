//
//  ShellModel+WorkspaceManagement.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import OSLog
import SwiftUI

// MARK: - Workspace Lifecycle
// MARK: Workspace creation, duplication, close, restore, and library persistence flows.

extension ShellModel {
	@discardableResult
	func createWorkspace() -> WorkspaceID {
		let pane = PaneLeaf()
		let workspace = Workspace(
			title: uniqueWorkspaceTitle(startingWith: "Workspace \(workspaces.count + 1)"),
			root: .leaf(pane),
			focusedPaneID: pane.id
		)

		workspaces.append(workspace)
		_ = sessions.ensureSession(
			id: pane.sessionID,
			launchConfiguration: launchContextBuilder.makeLaunchConfiguration()
		)
		paneFocusHistoryByWorkspace[workspace.id] = [pane.id]
		workspaceLogger.notice("Created a new workspace and seeded it with an initial pane. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public)")
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
		workspaceLogger.notice("Renamed a workspace. Previous title: \(previousTitle, privacy: .public). New title: \(trimmedTitle, privacy: .public). Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
		schedulePersistenceSave()
	}

	@discardableResult
	func duplicateWorkspace(_ workspaceID: WorkspaceID) -> WorkspaceID? {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return nil
		}

		let duplicatedWorkspace = duplicatedWorkspace(from: workspaces[workspaceIndex])
		workspaces.insert(duplicatedWorkspace, at: workspaceIndex + 1)
		paneFocusHistoryByWorkspace[duplicatedWorkspace.id] = [duplicatedWorkspace.focusedPaneID].compactMap { $0 }
		workspaceLogger.notice("Duplicated a workspace layout into a new workspace. Source workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public). New workspace title: \(duplicatedWorkspace.title, privacy: .public). New workspace ID: \(duplicatedWorkspace.id.rawValue.uuidString, privacy: .public)")
		schedulePersistenceSave()
		return duplicatedWorkspace.id
	}

	func canDeleteWorkspace(_ workspaceID: WorkspaceID) -> Bool {
		workspaces.count > 1 && workspaces.contains(where: { $0.id == workspaceID })
	}

	func closeWorkspace(_ workspaceID: WorkspaceID) -> WorkspaceID? {
		removeWorkspace(
			workspaceID,
			closeEffects: WorkspaceCloseEffects(
				recordRecentlyClosed: UserDefaults.standard.bool(
					forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey
				),
				saveToLibrary: UserDefaults.standard.bool(
					forKey: WorkspacePersistenceDefaults.autoSaveClosedWorkspacesKey
				)
			)
		)
	}

	func deleteWorkspace(_ workspaceID: WorkspaceID) {
		guard canDeleteWorkspace(workspaceID) else {
			return
		}

		_ = removeWorkspace(
			workspaceID,
			closeEffects: WorkspaceCloseEffects(
				recordRecentlyClosed: false,
				saveToLibrary: false
			)
		)
	}

	func canUndoCloseWorkspace() -> Bool {
		recentlyClosedWorkspaceCount > 0
	}

	@discardableResult
	func undoCloseWorkspace() -> WorkspaceID? {
		guard let closedWorkspace = recentlyClosedWorkspaces.popLast() else {
			return nil
		}

		let insertionIndex = min(closedWorkspace.formerIndex, workspaces.count)
		workspaces.insert(closedWorkspace.workspace, at: insertionIndex)
		paneFocusHistoryByWorkspace[closedWorkspace.workspace.id] = [closedWorkspace.workspace.focusedPaneID].compactMap { $0 }

		for leaf in closedWorkspace.workspace.paneLeaves {
			let launchConfiguration = closedWorkspace.launchConfigurationsBySessionID[leaf.sessionID]
				?? launchContextBuilder.makeLaunchConfiguration()
			_ = sessions.ensureSession(id: leaf.sessionID, launchConfiguration: launchConfiguration)
		}

		recentlyClosedWorkspaceCount = recentlyClosedWorkspaces.count
		workspaceLogger.notice("Reopened a recently closed workspace from the in-memory history stack. Workspace title: \(closedWorkspace.workspace.title, privacy: .public). Workspace ID: \(closedWorkspace.workspace.id.rawValue.uuidString, privacy: .public)")
		schedulePersistenceSave()
		return closedWorkspace.workspace.id
	}

	func clearRecentlyClosedWorkspaces() {
		recentlyClosedWorkspaces.removeAll()
		recentlyClosedWorkspaceCount = 0
		workspaceLogger.notice("Cleared the in-memory recently closed workspace stack for the current app session.")
	}

	func listSavedWorkspaceSnapshots(matching query: String? = nil) -> [SavedWorkspaceSnapshotSummary] {
		persistence.listWorkspaceSnapshots(matching: query)
	}

	@discardableResult
	func saveWorkspaceToLibrary(
		_ workspaceID: WorkspaceID,
		transcriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> SavedWorkspaceSnapshotSummary? {
		guard let workspace = workspaces.first(where: { $0.id == workspaceID }) else {
			workspaceLogger.error("The app was asked to save a workspace to the library, but that workspace no longer exists in the current shell model. Workspace ID: \(workspaceID.rawValue.uuidString, privacy: .public)")
			return nil
		}

		let resolvedTranscripts = snapshotTranscripts(
			for: workspace,
			explicitTranscriptsBySessionID: transcriptsBySessionID
		)

		let summary = persistence.createWorkspaceSnapshot(
			from: workspace,
			sessions: sessions,
			transcriptsBySessionID: resolvedTranscripts
		)
		if let summary {
			workspaceLogger.notice("Saved a workspace to the library. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public). Snapshot ID: \(summary.id.rawValue.uuidString, privacy: .public)")
		}
		return summary
	}

	@discardableResult
	func closeWorkspaceToLibrary(
		_ workspaceID: WorkspaceID,
		transcriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> WorkspaceID? {
		return removeWorkspace(
			workspaceID,
			closeEffects: WorkspaceCloseEffects(
				recordRecentlyClosed: UserDefaults.standard.bool(
					forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey
				),
				saveToLibrary: true
			),
			explicitTranscriptsBySessionID: transcriptsBySessionID
		)
	}

	@discardableResult
	func openSavedWorkspace(_ snapshotID: WorkspaceSnapshotID) -> WorkspaceID? {
		guard let snapshot = persistence.loadWorkspaceSnapshot(id: snapshotID) else {
			workspaceLogger.error("The app could not reopen a saved workspace because the requested library snapshot was missing or unreadable. Check the persistence logs for the exact load failure. Snapshot ID: \(snapshotID.rawValue.uuidString, privacy: .public)")
			return nil
		}

		let restoredWorkspace = restoredWorkspace(from: snapshot)
		workspaces.append(restoredWorkspace.workspace)
		paneFocusHistoryByWorkspace[restoredWorkspace.workspace.id] = [restoredWorkspace.workspace.focusedPaneID].compactMap { $0 }

		for (sessionID, launchConfiguration) in restoredWorkspace.launchConfigurationsBySessionID {
			let session = sessions.ensureSession(id: sessionID, launchConfiguration: launchConfiguration)
			session.title = restoredWorkspace.titlesBySessionID[sessionID] ?? "Shell"
			session.currentDirectory = launchConfiguration.currentDirectory
			session.setRestoredTranscript(restoredWorkspace.transcriptsBySessionID[sessionID])
		}

		persistence.markWorkspaceSnapshotOpened(snapshotID)
		workspaceLogger.notice("Opened a workspace from the saved-workspace library. Snapshot title: \(snapshot.title, privacy: .public). Snapshot ID: \(snapshotID.rawValue.uuidString, privacy: .public). Restored pane count: \(restoredWorkspace.workspace.paneCount)")
		schedulePersistenceSave()
		return restoredWorkspace.workspace.id
	}

	func deleteSavedWorkspace(_ snapshotID: WorkspaceSnapshotID) {
		guard persistence.deleteWorkspaceSnapshot(id: snapshotID) else {
			workspaceLogger.error("The app could not delete a saved workspace snapshot from the library because persistence did not confirm the deletion. Check the persistence logs for the exact failure. Snapshot ID: \(snapshotID.rawValue.uuidString, privacy: .public)")
			return
		}

		workspaceLogger.notice("Deleted a saved workspace snapshot from the library. Snapshot ID: \(snapshotID.rawValue.uuidString, privacy: .public)")
	}

}

// MARK: - Workspace Helpers
// MARK: Internal helpers that support workspace cloning, restore, close, and persistence workflows.

extension ShellModel {
	struct RecentlyClosedWorkspace {
		let workspace: Workspace
		let formerIndex: Int
		let launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration]
	}

	struct WorkspaceCloseEffects {
		let recordRecentlyClosed: Bool
		let saveToLibrary: Bool
	}

	struct RestoredWorkspace {
		let workspace: Workspace
		let launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration]
		let transcriptsBySessionID: [TerminalSessionID: String]
		let titlesBySessionID: [TerminalSessionID: String]
	}

	private func restoredWorkspaceTitle(startingWith baseTitle: String) -> String {
		let normalizedBaseTitle = baseTitle.trimmingCharacters(in: .whitespacesAndNewlines)
		let resolvedBaseTitle = normalizedBaseTitle.isEmpty ? "Workspace" : normalizedBaseTitle
		let existingTitles = Set(workspaces.map(\.title))
		guard existingTitles.contains(resolvedBaseTitle) else {
			return resolvedBaseTitle
		}

		let openedTimestamp = Date.now.formatted(date: .omitted, time: .shortened)
		return uniqueWorkspaceTitle(startingWith: "\(resolvedBaseTitle) (Opened \(openedTimestamp))")
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

	private func duplicatedWorkspace(from workspace: Workspace) -> Workspace {
		var clonedFocusedPaneID: PaneID?
		let clonedRoot = workspace.root.map {
			duplicateNode(
				$0,
				focusedPaneID: workspace.focusedPaneID,
				clonedFocusedPaneID: &clonedFocusedPaneID
			)
		}

		return Workspace(
			title: uniqueWorkspaceTitle(startingWith: "\(workspace.title) Copy"),
			root: clonedRoot,
			focusedPaneID: clonedFocusedPaneID
		)
	}

	private func duplicateNode(
		_ node: PaneNode,
		focusedPaneID: PaneID?,
		clonedFocusedPaneID: inout PaneID?
	) -> PaneNode {
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
				if leaf.id == focusedPaneID {
					clonedFocusedPaneID = clonedLeaf.id
				}
				return .leaf(clonedLeaf)

			case .split(let split):
				return .split(
					PaneSplit(
						axis: split.axis,
						fraction: split.fraction,
						first: duplicateNode(
							split.first,
							focusedPaneID: focusedPaneID,
							clonedFocusedPaneID: &clonedFocusedPaneID
						),
						second: duplicateNode(
							split.second,
							focusedPaneID: focusedPaneID,
							clonedFocusedPaneID: &clonedFocusedPaneID
						)
					)
				)
		}
	}

	func schedulePersistenceSave() {
		pendingPersistenceTask?.cancel()
		let workspacesSnapshot = workspaces
		pendingPersistenceTask = Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(250))
			guard !Task.isCancelled else {
				return
			}
			persistence.save(workspaces: workspacesSnapshot)
		}
	}

	@discardableResult
	func removeWorkspace(
		_ workspaceID: WorkspaceID,
		closeEffects: WorkspaceCloseEffects,
		explicitTranscriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> WorkspaceID? {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return nil
		}

		let workspace = workspaces[workspaceIndex]
		if closeEffects.saveToLibrary {
			let resolvedTranscripts = snapshotTranscripts(
				for: workspace,
				explicitTranscriptsBySessionID: explicitTranscriptsBySessionID
			)
			_ = persistence.createWorkspaceSnapshot(
				from: workspace,
				sessions: sessions,
				transcriptsBySessionID: resolvedTranscripts
			)
		}

		if closeEffects.recordRecentlyClosed {
			recordRecentlyClosedWorkspace(workspace, formerIndex: workspaceIndex)
		}

		workspaces.remove(at: workspaceIndex)
		paneFramesByWorkspace.removeValue(forKey: workspaceID)
		paneFocusHistoryByWorkspace.removeValue(forKey: workspaceID)
		removeUnreferencedSessions()

		let nextSelectedWorkspaceID: WorkspaceID?
		if workspaces.isEmpty {
			nextSelectedWorkspaceID = nil
		} else {
			let nextIndex = min(workspaceIndex, workspaces.count - 1)
			nextSelectedWorkspaceID = workspaces[nextIndex].id
		}

		workspaceLogger.notice("Closed a workspace from the live shell. Workspace title: \(workspace.title, privacy: .public). Workspace ID: \(workspace.id.rawValue.uuidString, privacy: .public). Recorded in recently closed: \(closeEffects.recordRecentlyClosed). Saved to library: \(closeEffects.saveToLibrary)")
		schedulePersistenceSave()
		return nextSelectedWorkspaceID
	}

	private func recordRecentlyClosedWorkspace(_ workspace: Workspace, formerIndex: Int) {
		guard UserDefaults.standard.bool(forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey) else {
			return
		}

		let launchConfigurationsBySessionID = Dictionary(uniqueKeysWithValues: workspace.paneLeaves.map { leaf in
			let session = sessions.ensureSession(id: leaf.sessionID)
			let currentDirectory = session.currentDirectory ?? session.launchConfiguration.currentDirectory
			let launchConfiguration = launchContextBuilder.makeLaunchConfiguration(
				currentDirectory: currentDirectory
			)
			return (leaf.sessionID, launchConfiguration)
		})

		recentlyClosedWorkspaces.removeAll { $0.workspace.id == workspace.id }
		recentlyClosedWorkspaces.append(
			RecentlyClosedWorkspace(
				workspace: workspace,
				formerIndex: formerIndex,
				launchConfigurationsBySessionID: launchConfigurationsBySessionID
			)
		)
		if recentlyClosedWorkspaces.count > WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount {
			recentlyClosedWorkspaces.removeFirst(
				recentlyClosedWorkspaces.count - WorkspacePersistenceDefaults.maxRecentlyClosedWorkspaceCount
			)
		}
		recentlyClosedWorkspaceCount = recentlyClosedWorkspaces.count
	}

	private func snapshotTranscripts(
		for workspace: Workspace,
		explicitTranscriptsBySessionID: [TerminalSessionID: String]
	) -> [TerminalSessionID: String] {
		var resolvedTranscripts = explicitTranscriptsBySessionID

		for leaf in workspace.paneLeaves where resolvedTranscripts[leaf.sessionID] == nil {
			guard
				let controller = paneControllers.existingController(for: leaf.id),
				let transcript = controller.captureTranscript()
			else {
				continue
			}

			resolvedTranscripts[leaf.sessionID] = transcript
		}

		return resolvedTranscripts
	}

	private func restoredWorkspace(from snapshot: SavedWorkspaceSnapshot) -> RestoredWorkspace {
		var launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration] = [:]
		var transcriptsBySessionID: [TerminalSessionID: String] = [:]
		var titlesBySessionID: [TerminalSessionID: String] = [:]
		var restoredFocusedPaneID: PaneID?
		let restoredRoot = snapshot.workspace.root.map {
			restoreNode(
				$0,
				focusedPaneID: snapshot.workspace.focusedPaneID,
				paneSnapshotsBySessionID: snapshot.paneSnapshotsBySessionID,
				launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
				transcriptsBySessionID: &transcriptsBySessionID,
				titlesBySessionID: &titlesBySessionID,
				restoredFocusedPaneID: &restoredFocusedPaneID
			)
		}

		let workspace = Workspace(
			title: restoredWorkspaceTitle(startingWith: snapshot.title),
			root: restoredRoot,
			focusedPaneID: restoredFocusedPaneID
		)

		return RestoredWorkspace(
			workspace: workspace,
			launchConfigurationsBySessionID: launchConfigurationsBySessionID,
			transcriptsBySessionID: transcriptsBySessionID,
			titlesBySessionID: titlesBySessionID
		)
	}

	private func restoreNode(
		_ node: PaneNode,
		focusedPaneID: PaneID?,
		paneSnapshotsBySessionID: [TerminalSessionID: SavedPaneSessionSnapshot],
		launchConfigurationsBySessionID: inout [TerminalSessionID: TerminalLaunchConfiguration],
		transcriptsBySessionID: inout [TerminalSessionID: String],
		titlesBySessionID: inout [TerminalSessionID: String],
		restoredFocusedPaneID: inout PaneID?
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
				if leaf.id == focusedPaneID {
					restoredFocusedPaneID = restoredLeaf.id
				}
				return .leaf(restoredLeaf)

			case .split(let split):
				return .split(
					PaneSplit(
						axis: split.axis,
						fraction: split.fraction,
						first: restoreNode(
							split.first,
							focusedPaneID: focusedPaneID,
							paneSnapshotsBySessionID: paneSnapshotsBySessionID,
							launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
							transcriptsBySessionID: &transcriptsBySessionID,
							titlesBySessionID: &titlesBySessionID,
							restoredFocusedPaneID: &restoredFocusedPaneID
						),
						second: restoreNode(
							split.second,
							focusedPaneID: focusedPaneID,
							paneSnapshotsBySessionID: paneSnapshotsBySessionID,
							launchConfigurationsBySessionID: &launchConfigurationsBySessionID,
							transcriptsBySessionID: &transcriptsBySessionID,
							titlesBySessionID: &titlesBySessionID,
							restoredFocusedPaneID: &restoredFocusedPaneID
						)
					)
				)
		}
	}
}
