//
//  TerminalSession.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation
import Combine

struct TerminalLaunchConfiguration: Hashable {
	var executable: String
	var arguments: [String]
	var environment: [String]?
	var currentDirectory: String?

	nonisolated static var loginShell: TerminalLaunchConfiguration {
		TerminalLaunchConfiguration(
			executable: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
			arguments: ["-l"],
			environment: nil,
			currentDirectory: nil
		)
	}
}

enum TerminalSessionState: Equatable {
	case idle
	case running
	case exited(Int32?)
}

@MainActor
final class TerminalSession: ObservableObject, Identifiable {
	let id: TerminalSessionID
	let launchConfiguration: TerminalLaunchConfiguration

	@Published var title: String
	@Published var currentDirectory: String?
	@Published var state: TerminalSessionState

	init(
		id: TerminalSessionID,
		launchConfiguration: TerminalLaunchConfiguration = .loginShell,
		title: String = "Shell",
		currentDirectory: String? = nil,
		state: TerminalSessionState = .idle
	) {
		self.id = id
		self.launchConfiguration = launchConfiguration
		self.title = title
		self.currentDirectory = currentDirectory
		self.state = state
	}
}

@MainActor
final class TerminalSessionRegistry {
	private let defaultLaunchConfiguration: TerminalLaunchConfiguration
	private var sessionsByID: [TerminalSessionID: TerminalSession]

	init(
		workspaces: [Workspace],
		defaultLaunchConfiguration: TerminalLaunchConfiguration = .loginShell
	) {
		self.defaultLaunchConfiguration = defaultLaunchConfiguration
		self.sessionsByID = [:]
		for workspace in workspaces {
			for leaf in workspace.paneLeaves {
				sessionsByID[leaf.sessionID] = TerminalSession(
					id: leaf.sessionID,
					launchConfiguration: defaultLaunchConfiguration,
					currentDirectory: defaultLaunchConfiguration.currentDirectory
				)
			}
		}
	}

	func ensureSession(
		id: TerminalSessionID,
		launchConfiguration: TerminalLaunchConfiguration? = nil
	) -> TerminalSession {
		if let session = sessionsByID[id] {
			return session
		}

		let resolvedLaunchConfiguration = launchConfiguration ?? defaultLaunchConfiguration
		let session = TerminalSession(
			id: id,
			launchConfiguration: resolvedLaunchConfiguration,
			currentDirectory: resolvedLaunchConfiguration.currentDirectory
		)
		sessionsByID[id] = session
		return session
	}

	func session(for id: TerminalSessionID) -> TerminalSession? {
		sessionsByID[id]
	}

	func removeSessions(notIn retainedSessionIDs: Set<TerminalSessionID>) {
		sessionsByID = sessionsByID.filter { retainedSessionIDs.contains($0.key) }
	}
}

@MainActor
final class TerminalPaneControllerStore {
	private var controllersByPaneID: [PaneID: TerminalPaneController] = [:]

	func controller(for pane: PaneLeaf, session: TerminalSession) -> TerminalPaneController {
		if let controller = controllersByPaneID[pane.id] {
			return controller
		}

		let controller = TerminalPaneController(paneID: pane.id, session: session)
		controllersByPaneID[pane.id] = controller
		return controller
	}

	func removeControllers(notIn retainedPaneIDs: Set<PaneID>) {
		controllersByPaneID = controllersByPaneID.filter { retainedPaneIDs.contains($0.key) }
	}
}

@MainActor
final class TerminalPaneController: ObservableObject {
	let paneID: PaneID
	let session: TerminalSession

	init(paneID: PaneID, session: TerminalSession) {
		self.paneID = paneID
		self.session = session
	}
}
