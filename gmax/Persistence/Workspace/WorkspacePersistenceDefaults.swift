/*
 WorkspacePersistenceDefaults defines the user-defaults keys and policy helpers
 that shape workspace restoration behavior. It centralizes restore-on-launch and
 recently-closed workspace settings so the workspace and settings layers share
 one durable configuration surface.
 */

import Foundation

enum WorkspacePersistenceDefaults {
	static let restoreWorkspacesOnLaunchKey = "workspacePersistence.restoreOnLaunch"
	static let keepRecentlyClosedWorkspacesKey = "workspacePersistence.keepRecentlyClosed"
	static let autoSaveClosedWorkspacesKey = "workspacePersistence.autoSaveClosedWorkspaces"
	static let maxRecentlyClosedWorkspaceCount = 20

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
