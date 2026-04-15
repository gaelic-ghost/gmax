//
//  TerminalSessionRegistry.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import Foundation

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
			for leaf in workspace.root?.leaves() ?? [] {
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
