//
//  ShellModel.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import Combine
import SwiftUI

struct WorkspaceID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

struct PaneID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

struct SplitID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

struct TerminalSessionID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

struct WorkspaceSnapshotID: RawRepresentable, Hashable, Codable, Identifiable {
	var rawValue: UUID

	var id: UUID { rawValue }

	init(rawValue: UUID) {
		self.rawValue = rawValue
	}

	init() {
		self.rawValue = UUID()
	}
}

enum SplitDirection {
	case right
	case down
}

enum PaneFocusDirection {
	case next
	case previous
	case left
	case right
	case up
	case down
}

enum CloseCommandResult {
	case closedPane
	case closedWorkspace
	case closeWindow
	case noAction
}

struct CloseCommandOutcome {
	let result: CloseCommandResult
	let nextSelectedWorkspaceID: WorkspaceID?
}

enum WorkspacePersistenceDefaults {
	static let restoreWorkspacesOnLaunchKey = "workspacePersistence.restoreOnLaunch"
	static let keepRecentlyClosedWorkspacesKey = "workspacePersistence.keepRecentlyClosed"
	static let autoSaveClosedWorkspacesKey = "workspacePersistence.autoSaveClosedWorkspaces"
	static let maxRecentlyClosedWorkspaceCount = 20

	static func registerDefaults(
		in defaults: UserDefaults = .standard,
		globalDefaults: UserDefaults = .standard
	) {
		defaults.register(
			defaults: [
				restoreWorkspacesOnLaunchKey: systemRestoresWindowsByDefault(globalDefaults: globalDefaults),
				keepRecentlyClosedWorkspacesKey: true,
				autoSaveClosedWorkspacesKey: false
			]
		)
	}

	static func systemRestoresWindowsByDefault(globalDefaults: UserDefaults = .standard) -> Bool {
		guard
			let globalDomain = globalDefaults.persistentDomain(forName: UserDefaults.globalDomain),
			let keepsWindows = globalDomain["NSQuitAlwaysKeepsWindows"] as? Bool
		else {
			return true
		}

		return keepsWindows
	}
}

struct Workspace: Identifiable, Hashable, Codable {
	var id: WorkspaceID
	var title: String
	var root: PaneNode?
	var focusedPaneID: PaneID?

	init(
		id: WorkspaceID = WorkspaceID(),
		title: String,
		root: PaneNode? = nil,
		focusedPaneID: PaneID? = nil
	) {
		self.id = id
		self.title = title
		self.root = root
		self.focusedPaneID = focusedPaneID
	}
}

extension Workspace {
	var paneLeaves: [PaneLeaf] {
		root?.leaves() ?? []
	}

	var paneCount: Int {
		root?.paneCount() ?? 0
	}
}

indirect enum PaneNode: Hashable, Codable {
	case leaf(PaneLeaf)
	case split(PaneSplit)
}

struct PaneLeaf: Identifiable, Hashable, Codable {
	var id: PaneID
	var sessionID: TerminalSessionID

	init(id: PaneID = PaneID(), sessionID: TerminalSessionID = TerminalSessionID()) {
		self.id = id
		self.sessionID = sessionID
	}
}

struct PaneSplit: Hashable, Codable {
	enum Axis: String, Hashable, Codable {
		case horizontal
		case vertical
	}

	var id: SplitID
	var axis: Axis
	var fraction: CGFloat
	var first: PaneNode
	var second: PaneNode

	init(
		id: SplitID = SplitID(),
		axis: Axis,
		fraction: CGFloat,
		first: PaneNode,
		second: PaneNode
	) {
		self.id = id
		self.axis = axis
		self.fraction = fraction
		self.first = first
		self.second = second
	}
}

struct SavedPaneSessionSnapshot: Hashable, Codable, Identifiable {
	var id: TerminalSessionID
	var title: String
	var launchConfiguration: TerminalLaunchConfiguration
	var transcript: String?
	var transcriptByteCount: Int
	var transcriptLineCount: Int
	var previewText: String?
}

struct SavedWorkspaceSnapshotSummary: Identifiable, Hashable, Codable {
	var id: WorkspaceSnapshotID
	var title: String
	var createdAt: Date
	var updatedAt: Date
	var lastOpenedAt: Date?
	var isPinned: Bool
	var previewText: String?
	var paneCount: Int
}

struct SavedWorkspaceSnapshot: Identifiable, Hashable, Codable {
	var id: WorkspaceSnapshotID
	var title: String
	var createdAt: Date
	var updatedAt: Date
	var lastOpenedAt: Date?
	var isPinned: Bool
	var notes: String?
	var previewText: String?
	var workspace: Workspace
	var paneSnapshotsBySessionID: [TerminalSessionID: SavedPaneSessionSnapshot]
}

enum PaneRemovalResult {
	case removedLeaf
	case collapsedTo(PaneNode)
}

extension PaneNode {
	func leaves() -> [PaneLeaf] {
		switch self {
			case .leaf(let leaf):
				return [leaf]
			case .split(let split):
				return split.first.leaves() + split.second.leaves()
		}
	}

	func findPane(id: PaneID) -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf.id == id ? leaf : nil
			case .split(let split):
				return split.first.findPane(id: id) ?? split.second.findPane(id: id)
		}
	}

	func containsPane(id: PaneID) -> Bool {
		findPane(id: id) != nil
	}

	func firstLeaf() -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf
			case .split(let split):
				return split.first.firstLeaf() ?? split.second.firstLeaf()
		}
	}

	func lastLeaf() -> PaneLeaf? {
		switch self {
			case .leaf(let leaf):
				return leaf
			case .split(let split):
				return split.second.lastLeaf() ?? split.first.lastLeaf()
		}
	}

	mutating func split(
		paneID: PaneID,
		direction: SplitDirection,
		newPane: PaneLeaf,
		initialFraction: CGFloat = 0.5
	) -> Bool {
		switch self {
			case .leaf(let leaf):
				guard leaf.id == paneID else {
					return false
				}

				let axis: PaneSplit.Axis = switch direction {
					case .right: .horizontal
					case .down: .vertical
				}

				self = .split(
					PaneSplit(
						axis: axis,
						fraction: initialFraction,
						first: .leaf(leaf),
						second: .leaf(newPane)
					)
				)
				return true

			case .split(var split):
				if split.first.split(
					paneID: paneID,
					direction: direction,
					newPane: newPane,
					initialFraction: initialFraction
				) {
					self = .split(split)
					return true
				}

				if split.second.split(
					paneID: paneID,
					direction: direction,
					newPane: newPane,
					initialFraction: initialFraction
				) {
					self = .split(split)
					return true
				}

				return false
		}
	}

	mutating func removePane(id: PaneID) -> PaneRemovalResult? {
		switch self {
			case .leaf(let leaf):
				return leaf.id == id ? .removedLeaf : nil

			case .split(var split):
				if let result = split.first.removePane(id: id) {
					switch result {
						case .removedLeaf:
							self = split.second
							return .collapsedTo(split.second)
						case .collapsedTo(let node):
							split.first = node
							self = .split(split)
							return .collapsedTo(self)
					}
				}

				if let result = split.second.removePane(id: id) {
					switch result {
						case .removedLeaf:
							self = split.first
							return .collapsedTo(split.first)
						case .collapsedTo(let node):
							split.second = node
							self = .split(split)
							return .collapsedTo(self)
					}
				}

				return nil
		}
	}

	mutating func updateSplitFraction(splitID: SplitID, fraction: CGFloat) -> Bool {
		switch self {
			case .leaf:
				return false

			case .split(var split):
				if split.id == splitID {
					split.fraction = fraction
					self = .split(split)
					return true
				}

				if split.first.updateSplitFraction(splitID: splitID, fraction: fraction) {
					self = .split(split)
					return true
				}

				if split.second.updateSplitFraction(splitID: splitID, fraction: fraction) {
					self = .split(split)
					return true
				}

				return false
		}
	}

	func paneCount() -> Int {
		switch self {
			case .leaf:
				return 1
			case .split(let split):
				return split.first.paneCount() + split.second.paneCount()
		}
	}
}

@MainActor
final class ShellModel: ObservableObject {
	@Published var workspaces: [Workspace]
	@Published var columnVisibility: NavigationSplitViewVisibility
	@Published var isInspectorVisible: Bool
	@Published private(set) var recentlyClosedWorkspaceCount = 0

	let persistence: ShellPersistenceController
	let launchContextBuilder: TerminalLaunchContextBuilder
	let sessions: TerminalSessionRegistry
	let paneControllers: TerminalPaneControllerStore
	private var currentWorkspaceID: WorkspaceID?
	private var paneFramesByWorkspace: [WorkspaceID: [PaneID: CGRect]]
	private var paneFocusHistoryByWorkspace: [WorkspaceID: [PaneID]]
	private var pendingPersistenceTask: Task<Void, Never>?
	private var recentlyClosedWorkspaces: [RecentlyClosedWorkspace] = []

	init() {
		WorkspacePersistenceDefaults.registerDefaults()
		let persistence = ShellPersistenceController.shared
		let persistedWorkspaces = UserDefaults.standard.bool(
			forKey: WorkspacePersistenceDefaults.restoreWorkspacesOnLaunchKey
		) ? persistence.loadWorkspaces() : []
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

	@discardableResult
	func createWorkspace() -> WorkspaceID {
		let workspace = Self.makeDefaultWorkspace(
			title: uniqueWorkspaceTitle(startingWith: "Workspace \(workspaces.count + 1)")
		)
		guard let pane = workspace.root?.firstLeaf() else {
			workspaces.append(workspace)
			currentWorkspaceID = workspace.id
			schedulePersistenceSave()
			return workspace.id
		}

		workspaces.append(workspace)
		_ = sessions.ensureSession(
			id: pane.sessionID,
			launchConfiguration: launchContextBuilder.makeLaunchConfiguration()
		)
		currentWorkspaceID = workspace.id
		paneFocusHistoryByWorkspace[workspace.id] = [pane.id]
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

		workspaces[workspaceIndex].title = trimmedTitle
		schedulePersistenceSave()
	}

	@discardableResult
	func duplicateWorkspace(_ workspaceID: WorkspaceID) -> WorkspaceID? {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return nil
		}

		let duplicatedWorkspace = duplicatedWorkspace(from: workspaces[workspaceIndex])
		workspaces.insert(duplicatedWorkspace, at: workspaceIndex + 1)
		currentWorkspaceID = duplicatedWorkspace.id
		paneFocusHistoryByWorkspace[duplicatedWorkspace.id] = [duplicatedWorkspace.focusedPaneID].compactMap { $0 }
		schedulePersistenceSave()
		return duplicatedWorkspace.id
	}

	func canDeleteWorkspace(_ workspaceID: WorkspaceID) -> Bool {
		workspaces.count > 1 && workspaces.contains(where: { $0.id == workspaceID })
	}

	func closeWorkspace(_ workspaceID: WorkspaceID) -> CloseCommandOutcome {
		return removeWorkspace(workspaceID, closeEffects: defaultCloseEffects())
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
		currentWorkspaceID = closedWorkspace.workspace.id
		paneFocusHistoryByWorkspace[closedWorkspace.workspace.id] = [closedWorkspace.workspace.focusedPaneID].compactMap { $0 }

		for leaf in closedWorkspace.workspace.paneLeaves {
			let launchConfiguration = closedWorkspace.launchConfigurationsBySessionID[leaf.sessionID]
				?? launchContextBuilder.makeLaunchConfiguration()
			_ = sessions.ensureSession(id: leaf.sessionID, launchConfiguration: launchConfiguration)
		}

		updateRecentlyClosedWorkspaceCount()
		schedulePersistenceSave()
		return closedWorkspace.workspace.id
	}

	func clearRecentlyClosedWorkspaces() {
		recentlyClosedWorkspaces.removeAll()
		updateRecentlyClosedWorkspaceCount()
	}

	func listSavedWorkspaceSnapshots(matching query: String? = nil) -> [SavedWorkspaceSnapshotSummary] {
		persistence.listWorkspaceSnapshots(matching: query)
	}

	@discardableResult
	func saveWorkspaceToLibrary(
		_ workspaceID: WorkspaceID,
		transcriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> SavedWorkspaceSnapshotSummary? {
		guard let workspace = workspace(for: workspaceID) else {
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
		return summary
	}

	@discardableResult
	func saveSelectedWorkspaceToLibrary(
		transcriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> SavedWorkspaceSnapshotSummary? {
		guard let currentWorkspaceID else {
			return nil
		}

		return saveWorkspaceToLibrary(
			currentWorkspaceID,
			transcriptsBySessionID: transcriptsBySessionID
		)
	}

	@discardableResult
	func closeWorkspaceToLibrary(
		_ workspaceID: WorkspaceID,
		transcriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> CloseCommandOutcome {
		let defaultEffects = defaultCloseEffects()
		return removeWorkspace(
			workspaceID,
			closeEffects: WorkspaceCloseEffects(
				recordRecentlyClosed: defaultEffects.recordRecentlyClosed,
				saveToLibrary: true
			),
			explicitTranscriptsBySessionID: transcriptsBySessionID
		)
	}

	@discardableResult
	func openSavedWorkspace(_ snapshotID: WorkspaceSnapshotID) -> WorkspaceID? {
		guard let snapshot = persistence.loadWorkspaceSnapshot(id: snapshotID) else {
			return nil
		}

		let restoredWorkspace = restoredWorkspace(from: snapshot)
		workspaces.append(restoredWorkspace.workspace)
		currentWorkspaceID = restoredWorkspace.workspace.id
		paneFocusHistoryByWorkspace[restoredWorkspace.workspace.id] = [restoredWorkspace.workspace.focusedPaneID].compactMap { $0 }

		for (sessionID, launchConfiguration) in restoredWorkspace.launchConfigurationsBySessionID {
			let session = sessions.ensureSession(id: sessionID, launchConfiguration: launchConfiguration)
			session.title = restoredWorkspace.titlesBySessionID[sessionID] ?? "Shell"
			session.currentDirectory = launchConfiguration.currentDirectory
			session.setRestoredTranscript(restoredWorkspace.transcriptsBySessionID[sessionID])
		}

		persistence.markWorkspaceSnapshotOpened(snapshotID)
		schedulePersistenceSave()
		return restoredWorkspace.workspace.id
	}

	func deleteSavedWorkspace(_ snapshotID: WorkspaceSnapshotID) {
		persistence.deleteWorkspaceSnapshot(id: snapshotID)
	}

	func closeSelectedWorkspace() -> CloseCommandOutcome {
		guard let currentWorkspaceID else {
			return CloseCommandOutcome(result: .closeWindow, nextSelectedWorkspaceID: nil)
		}

		return closeWorkspace(currentWorkspaceID)
	}

	@discardableResult
	func createPane() -> WorkspaceID? {
		guard let workspace = selectedWorkspace else {
			return createWorkspace()
		}

		if workspace.root == nil {
			createInitialPane(in: workspace.id)
			return workspace.id
		}

		guard let paneID = workspace.focusedPaneID ?? workspace.root?.firstLeaf()?.id else {
			return workspace.id
		}
		splitPane(paneID, in: workspace.id, direction: .right)
		return workspace.id
	}

	@discardableResult
	func createPane(in workspaceID: WorkspaceID) -> WorkspaceID? {
		setCurrentWorkspaceID(workspaceID)
		return createPane()
	}

	func relaunchPane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		guard let workspace = workspace(for: workspaceID),
			  let pane = workspace.root?.findPane(id: paneID) else {
			return
		}

		let session = sessions.ensureSession(id: pane.sessionID)
		session.prepareForRelaunch()
		focusPane(paneID, in: workspaceID)
	}

	func relaunchFocusedPane() {
		guard
			let workspace = selectedWorkspace,
			let paneID = workspace.focusedPaneID
		else {
			return
		}

		relaunchPane(paneID, in: workspace.id)
	}

	func selectNextWorkspace() -> WorkspaceID? {
		guard !workspaces.isEmpty else {
			return nil
		}
		guard let selectedWorkspaceIndex else {
			currentWorkspaceID = workspaces.first?.id
			return currentWorkspaceID
		}

		let nextIndex = (selectedWorkspaceIndex + 1) % workspaces.count
		currentWorkspaceID = workspaces[nextIndex].id
		return currentWorkspaceID
	}

	func selectPreviousWorkspace() -> WorkspaceID? {
		guard !workspaces.isEmpty else {
			return nil
		}
		guard let selectedWorkspaceIndex else {
			currentWorkspaceID = workspaces.last?.id
			return currentWorkspaceID
		}

		let previousIndex = (selectedWorkspaceIndex - 1 + workspaces.count) % workspaces.count
		currentWorkspaceID = workspaces[previousIndex].id
		return currentWorkspaceID
	}

	func focusPane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard let root = workspaces[workspaceIndex].root,
			  root.containsPane(id: paneID)
		else {
			return
		}
		workspaces[workspaceIndex].focusedPaneID = paneID
		recordPaneFocus(paneID, in: workspaceID)
		schedulePersistenceSave()
	}

	func splitPane(_ paneID: PaneID, in workspaceID: WorkspaceID, direction: SplitDirection) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard var root = workspaces[workspaceIndex].root else {
			return
		}
		guard let sourcePane = root.findPane(id: paneID) else {
			return
		}

		let sourceSession = sessions.ensureSession(id: sourcePane.sessionID)
		let inheritedCurrentDirectory = sourceSession.currentDirectory
			?? sourceSession.launchConfiguration.currentDirectory

		let newPane = PaneLeaf()
		guard root.split(
			paneID: paneID,
			direction: direction,
			newPane: newPane
		) else {
			return
		}

		workspaces[workspaceIndex].root = root
		_ = sessions.ensureSession(
			id: newPane.sessionID,
			launchConfiguration: launchContextBuilder.makeLaunchConfiguration(
				currentDirectory: inheritedCurrentDirectory
			)
		)
		workspaces[workspaceIndex].focusedPaneID = newPane.id
		recordPaneFocus(newPane.id, in: workspaceID)
		schedulePersistenceSave()
	}

	func splitFocusedPane(_ direction: SplitDirection) {
		guard
			let workspace = selectedWorkspace,
			let paneID = workspace.focusedPaneID
		else {
			return
		}

		splitPane(paneID, in: workspace.id, direction: direction)
	}

	func splitFocusedPane(in workspaceID: WorkspaceID, _ direction: SplitDirection) {
		guard
			let workspace = workspace(for: workspaceID),
			let paneID = workspace.focusedPaneID
		else {
			return
		}

		splitPane(paneID, in: workspace.id, direction: direction)
	}

	func closePane(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard var root = workspaces[workspaceIndex].root else {
			return
		}

		let priorLeaves = root.leaves()
		let priorFocusedPaneID = workspaces[workspaceIndex].focusedPaneID

		guard root.removePane(id: paneID) != nil else {
			return
		}

		workspaces[workspaceIndex].root = root
		removeUnreferencedSessions()

		let survivingLeaves = workspaces[workspaceIndex].paneLeaves
		if let priorFocusedPaneID,
		   survivingLeaves.contains(where: { $0.id == priorFocusedPaneID }) {
			workspaces[workspaceIndex].focusedPaneID = priorFocusedPaneID
			recordPaneFocus(priorFocusedPaneID, in: workspaceID)
			schedulePersistenceSave()
			return
		}

		let removedPaneIndex = priorLeaves.firstIndex(where: { $0.id == paneID }) ?? survivingLeaves.endIndex
		let fallbackIndex = min(removedPaneIndex, survivingLeaves.count - 1)
		workspaces[workspaceIndex].focusedPaneID = survivingLeaves[fallbackIndex].id
		recordPaneFocus(survivingLeaves[fallbackIndex].id, in: workspaceID)
		schedulePersistenceSave()
	}

	@discardableResult
	func closeFocusedPane() -> CloseCommandOutcome {
		return performCloseCommand()
	}

	@discardableResult
	func closeFocusedPane(in workspaceID: WorkspaceID) -> CloseCommandOutcome {
		guard let workspace = workspace(for: workspaceID) else {
			return CloseCommandOutcome(result: .noAction, nextSelectedWorkspaceID: normalizedWorkspaceSelection(currentWorkspaceID))
		}

		guard let focusedPaneID = workspace.focusedPaneID else {
			return CloseCommandOutcome(result: .noAction, nextSelectedWorkspaceID: normalizedWorkspaceSelection(currentWorkspaceID))
		}

		if workspace.paneCount == 1 {
			return removeWorkspace(workspace.id, closeEffects: defaultCloseEffects())
		}

		closePane(focusedPaneID, in: workspace.id)
		return CloseCommandOutcome(result: .closedPane, nextSelectedWorkspaceID: normalizedWorkspaceSelection(currentWorkspaceID))
	}

	func movePaneFocus(_ direction: PaneFocusDirection) {
		guard let workspaceIndex = selectedWorkspaceIndex else {
			return
		}

		let leaves = workspaces[workspaceIndex].paneLeaves
		guard !leaves.isEmpty else { return }

		guard let focusedPaneID = workspaces[workspaceIndex].focusedPaneID,
			  let focusedIndex = leaves.firstIndex(where: { $0.id == focusedPaneID })
		else {
			let fallbackPane = direction == .next ? leaves.first : leaves.last
			workspaces[workspaceIndex].focusedPaneID = fallbackPane?.id
			return
		}

		let nextIndex: Int
		switch direction {
			case .next:
				nextIndex = (focusedIndex + 1) % leaves.count
			case .previous:
				nextIndex = (focusedIndex - 1 + leaves.count) % leaves.count
			case .left, .right, .up, .down:
				guard let nextPaneID = directionalPaneFocus(
					from: focusedPaneID,
					in: workspaces[workspaceIndex].id,
					direction: direction
				) else {
					return
				}
				workspaces[workspaceIndex].focusedPaneID = nextPaneID
				recordPaneFocus(nextPaneID, in: workspaces[workspaceIndex].id)
				return
		}

		workspaces[workspaceIndex].focusedPaneID = leaves[nextIndex].id
		recordPaneFocus(leaves[nextIndex].id, in: workspaces[workspaceIndex].id)
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
	}

	func toggleInspector() {
		isInspectorVisible.toggle()
	}

	func setInspectorVisible(_ isVisible: Bool) {
		isInspectorVisible = isVisible
	}

	func controller(for pane: PaneLeaf) -> TerminalPaneController {
		let session = sessions.ensureSession(id: pane.sessionID)
		return paneControllers.controller(for: pane, session: session)
	}

	func setSplitFraction(_ fraction: CGFloat, for splitID: SplitID, in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}
		guard var root = workspaces[workspaceIndex].root else {
			return
		}

		guard root.updateSplitFraction(splitID: splitID, fraction: fraction) else {
			return
		}
		workspaces[workspaceIndex].root = root
		schedulePersistenceSave()
	}

	func updatePaneFrames(_ paneFrames: [PaneID: CGRect], in workspaceID: WorkspaceID) {
		paneFramesByWorkspace[workspaceID] = paneFrames
	}

	private func removeUnreferencedSessions() {
		let activeLeaves = workspaces.flatMap { workspace in
			workspace.paneLeaves.map { (workspace.id, $0) }
		}
		let activeSessionIDs = Set(activeLeaves.map(\.1.sessionID))
		let activePaneIDsByWorkspace = Dictionary(grouping: activeLeaves, by: \.0)
			.mapValues { Set($0.map(\.1.id)) }
		sessions.removeSessions(notIn: activeSessionIDs)
		paneControllers.removeControllers(notIn: Set(activeLeaves.map(\.1.id)))

		var filteredFramesByWorkspace: [WorkspaceID: [PaneID: CGRect]] = [:]
		for (workspaceID, frames) in paneFramesByWorkspace {
			guard let activePaneIDs = activePaneIDsByWorkspace[workspaceID] else {
				continue
			}
			let filteredFrames = frames.filter { activePaneIDs.contains($0.key) }
			if !filteredFrames.isEmpty {
				filteredFramesByWorkspace[workspaceID] = filteredFrames
			}
		}
		paneFramesByWorkspace = filteredFramesByWorkspace

		var filteredFocusHistoryByWorkspace: [WorkspaceID: [PaneID]] = [:]
		for (workspaceID, history) in paneFocusHistoryByWorkspace {
			guard let activePaneIDs = activePaneIDsByWorkspace[workspaceID] else {
				continue
			}
			let filteredHistory = history.filter { activePaneIDs.contains($0) }
			if !filteredHistory.isEmpty {
				filteredFocusHistoryByWorkspace[workspaceID] = filteredHistory
			}
		}
		paneFocusHistoryByWorkspace = filteredFocusHistoryByWorkspace
	}

	private func recordPaneFocus(_ paneID: PaneID, in workspaceID: WorkspaceID) {
		var history = paneFocusHistoryByWorkspace[workspaceID, default: []]
		history.removeAll { $0 == paneID }
		history.append(paneID)
		paneFocusHistoryByWorkspace[workspaceID] = history
	}

	private func directionalPaneFocus(
		from paneID: PaneID,
		in workspaceID: WorkspaceID,
		direction: PaneFocusDirection
	) -> PaneID? {
		guard let currentFrame = paneFramesByWorkspace[workspaceID]?[paneID] else {
			return nil
		}

		let paneFrames = Array(paneFramesByWorkspace[workspaceID] ?? [:])
		let candidates: [(PaneID, PaneNavigationMetrics)] = paneFrames.compactMap { entry in
			let (candidatePaneID, candidateFrame) = entry
			guard candidatePaneID != paneID else {
				return nil
			}

			guard let metrics = navigationMetrics(
				from: currentFrame,
				to: candidateFrame,
				direction: direction,
				history: paneFocusHistoryByWorkspace[workspaceID, default: []],
				paneID: candidatePaneID
			) else {
				return nil
			}

			return (candidatePaneID, metrics)
		}

		return candidates.max { lhs, rhs in
			lhs.1 < rhs.1
		}?.0
	}

	private func navigationMetrics(
		from currentFrame: CGRect,
		to candidateFrame: CGRect,
		direction: PaneFocusDirection,
		history: [PaneID],
		paneID: PaneID
	) -> PaneNavigationMetrics? {
		let directionalDistance: CGFloat
		let perpendicularOverlap: CGFloat
		let perpendicularDistance: CGFloat

		switch direction {
			case .left:
				guard candidateFrame.midX < currentFrame.midX else { return nil }
				directionalDistance = max(currentFrame.minX - candidateFrame.maxX, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minY,
					currentMax: currentFrame.maxY,
					candidateMin: candidateFrame.minY,
					candidateMax: candidateFrame.maxY
				)
				perpendicularDistance = abs(candidateFrame.midY - currentFrame.midY)

			case .right:
				guard candidateFrame.midX > currentFrame.midX else { return nil }
				directionalDistance = max(candidateFrame.minX - currentFrame.maxX, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minY,
					currentMax: currentFrame.maxY,
					candidateMin: candidateFrame.minY,
					candidateMax: candidateFrame.maxY
				)
				perpendicularDistance = abs(candidateFrame.midY - currentFrame.midY)

			case .up:
				guard candidateFrame.midY < currentFrame.midY else { return nil }
				directionalDistance = max(currentFrame.minY - candidateFrame.maxY, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minX,
					currentMax: currentFrame.maxX,
					candidateMin: candidateFrame.minX,
					candidateMax: candidateFrame.maxX
				)
				perpendicularDistance = abs(candidateFrame.midX - currentFrame.midX)

			case .down:
				guard candidateFrame.midY > currentFrame.midY else { return nil }
				directionalDistance = max(candidateFrame.minY - currentFrame.maxY, 0)
				perpendicularOverlap = overlapLength(
					currentMin: currentFrame.minX,
					currentMax: currentFrame.maxX,
					candidateMin: candidateFrame.minX,
					candidateMax: candidateFrame.maxX
				)
				perpendicularDistance = abs(candidateFrame.midX - currentFrame.midX)

			case .next, .previous:
				return nil
		}

		let historyRank = history.lastIndex(of: paneID).map { history.distance(from: $0, to: history.endIndex) } ?? 0
		return PaneNavigationMetrics(
			hasPerpendicularOverlap: perpendicularOverlap > 0,
			perpendicularOverlap: perpendicularOverlap,
			directionalDistance: directionalDistance,
			perpendicularDistance: perpendicularDistance,
			historyRank: historyRank
		)
	}

	private func overlapLength(
		currentMin: CGFloat,
		currentMax: CGFloat,
		candidateMin: CGFloat,
		candidateMax: CGFloat
	) -> CGFloat {
		max(0, min(currentMax, candidateMax) - max(currentMin, candidateMin))
	}
}

extension ShellModel {
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
		let clonedRoot = workspace.root.map { duplicateNode($0, focusedPaneID: workspace.focusedPaneID, clonedFocusedPaneID: &clonedFocusedPaneID) }

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

	private static func makeDefaultWorkspace(title: String = "Workspace 1") -> Workspace {
		let pane = PaneLeaf()
		return Workspace(
			title: title,
			root: .leaf(pane),
			focusedPaneID: pane.id
		)
	}

	private func createInitialPane(in workspaceID: WorkspaceID) {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return
		}

		let pane = PaneLeaf()
		workspaces[workspaceIndex].root = .leaf(pane)
		workspaces[workspaceIndex].focusedPaneID = pane.id
		_ = sessions.ensureSession(
			id: pane.sessionID,
			launchConfiguration: launchContextBuilder.makeLaunchConfiguration()
		)
		recordPaneFocus(pane.id, in: workspaceID)
		schedulePersistenceSave()
	}

	private struct PaneNavigationMetrics: Comparable {
		let hasPerpendicularOverlap: Bool
		let perpendicularOverlap: CGFloat
		let directionalDistance: CGFloat
		let perpendicularDistance: CGFloat
		let historyRank: Int

		static func < (lhs: Self, rhs: Self) -> Bool {
			if lhs.hasPerpendicularOverlap != rhs.hasPerpendicularOverlap {
				return !lhs.hasPerpendicularOverlap && rhs.hasPerpendicularOverlap
			}
			if lhs.perpendicularOverlap != rhs.perpendicularOverlap {
				return lhs.perpendicularOverlap < rhs.perpendicularOverlap
			}
			if lhs.directionalDistance != rhs.directionalDistance {
				return lhs.directionalDistance > rhs.directionalDistance
			}
			if lhs.perpendicularDistance != rhs.perpendicularDistance {
				return lhs.perpendicularDistance > rhs.perpendicularDistance
			}
			return lhs.historyRank < rhs.historyRank
		}
	}

	private static func initialFocusHistory(for workspaces: [Workspace]) -> [WorkspaceID: [PaneID]] {
		Dictionary(uniqueKeysWithValues: workspaces.map { workspace in
			(workspace.id, [workspace.focusedPaneID].compactMap { $0 })
		})
	}

	private struct RecentlyClosedWorkspace {
		let workspace: Workspace
		let formerIndex: Int
		let launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration]
	}

	private struct WorkspaceCloseEffects {
		let recordRecentlyClosed: Bool
		let saveToLibrary: Bool
	}

	private struct RestoredWorkspace {
		let workspace: Workspace
		let launchConfigurationsBySessionID: [TerminalSessionID: TerminalLaunchConfiguration]
		let transcriptsBySessionID: [TerminalSessionID: String]
		let titlesBySessionID: [TerminalSessionID: String]
	}

	func performCloseCommand() -> CloseCommandOutcome {
		guard let workspaceIndex = selectedWorkspaceIndex else {
			return CloseCommandOutcome(result: .closeWindow, nextSelectedWorkspaceID: nil)
		}

		let workspace = workspaces[workspaceIndex]
		guard let focusedPaneID = workspace.focusedPaneID else {
			return CloseCommandOutcome(result: .noAction, nextSelectedWorkspaceID: currentWorkspaceID)
		}

		if workspace.paneCount == 1 {
			return removeWorkspace(workspace.id, closeEffects: defaultCloseEffects())
		}

		closePane(focusedPaneID, in: workspace.id)
		return CloseCommandOutcome(result: .closedPane, nextSelectedWorkspaceID: currentWorkspaceID)
	}

	private func schedulePersistenceSave() {
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
	private func removeWorkspace(
		_ workspaceID: WorkspaceID,
		closeEffects: WorkspaceCloseEffects,
		explicitTranscriptsBySessionID: [TerminalSessionID: String] = [:]
	) -> CloseCommandOutcome {
		guard let workspaceIndex = workspaces.firstIndex(where: { $0.id == workspaceID }) else {
			return CloseCommandOutcome(result: .noAction, nextSelectedWorkspaceID: currentWorkspaceID)
		}

		if workspaces.count == 1 {
			return CloseCommandOutcome(result: .closeWindow, nextSelectedWorkspaceID: nil)
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

		let wasSelectedWorkspace = currentWorkspaceID == workspaceID
		workspaces.remove(at: workspaceIndex)
		paneFramesByWorkspace.removeValue(forKey: workspaceID)
		paneFocusHistoryByWorkspace.removeValue(forKey: workspaceID)
		removeUnreferencedSessions()

		if wasSelectedWorkspace {
			let nextIndex = min(workspaceIndex, workspaces.count - 1)
			currentWorkspaceID = workspaces[nextIndex].id
		}

		schedulePersistenceSave()
		return CloseCommandOutcome(
			result: .closedWorkspace,
			nextSelectedWorkspaceID: normalizedWorkspaceSelection(currentWorkspaceID)
		)
	}

	private func defaultCloseEffects(defaults: UserDefaults = .standard) -> WorkspaceCloseEffects {
		WorkspaceCloseEffects(
			recordRecentlyClosed: defaults.bool(
				forKey: WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey
			),
			saveToLibrary: defaults.bool(
				forKey: WorkspacePersistenceDefaults.autoSaveClosedWorkspacesKey
			)
		)
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
		updateRecentlyClosedWorkspaceCount()
	}

	private func updateRecentlyClosedWorkspaceCount() {
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
