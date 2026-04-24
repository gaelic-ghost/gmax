/*
 WorkspacePersistenceDefaults defines the user-defaults keys and policy helpers
 that shape workspace restoration behavior. It centralizes restore-on-launch and
 recently-closed workspace settings so the workspace and settings layers share
 one durable configuration surface.
 */

import Foundation

enum WorkspacePersistenceDefaults {
    nonisolated static let restoreWorkspacesOnLaunchKey = "workspacePersistence.restoreOnLaunch"
    nonisolated static let keepRecentlyClosedWorkspacesKey = "workspacePersistence.keepRecentlyClosed"
    nonisolated static let autoSaveClosedItemsKey = "workspacePersistence.autoSaveClosedWorkspaces"
    nonisolated static let backgroundSaveIntervalMinutesKey = "workspacePersistence.backgroundSaveIntervalMinutes"
    nonisolated static let launchRestoreWindowIDsKey = "workspacePersistence.launchRestoreWindowIDs"
    nonisolated static let maxRecentlyClosedWorkspaceCount = 20
    nonisolated static let defaultBackgroundSaveIntervalMinutes = 5

    nonisolated static func systemRestoresWindowsByDefault(globalDefaults: UserDefaults = .standard) -> Bool {
        guard
            let globalDomain = globalDefaults.persistentDomain(forName: UserDefaults.globalDomain),
            let keepsWindows = globalDomain["NSQuitAlwaysKeepsWindows"] as? Bool
        else {
            return true
        }

        return keepsWindows
    }

    nonisolated static func restoreWorkspacesOnLaunch(
        userDefaults: UserDefaults = .standard,
        globalDefaults: UserDefaults = .standard,
    ) -> Bool {
        if let explicitValue = userDefaults.object(forKey: restoreWorkspacesOnLaunchKey) as? Bool {
            return explicitValue
        }

        return systemRestoresWindowsByDefault(globalDefaults: globalDefaults)
    }

    nonisolated static func normalizedBackgroundSaveIntervalMinutes(_ minutes: Int) -> Int {
        max(1, minutes)
    }

    nonisolated static func autoSavesClosedItems(
        userDefaults: UserDefaults = .standard,
    ) -> Bool {
        userDefaults.bool(forKey: autoSaveClosedItemsKey)
    }
}
