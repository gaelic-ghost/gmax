//
//  ExperimentalSettingsDefaults.swift
//  gmax
//
//  Created by Codex on 4/28/26.
//

import Foundation

enum ExperimentalSettingsDefaults {
    static let useGhosttyForNewTerminalPanesKey = "experimental.useGhosttyForNewTerminalPanes"
    static let ghosttyEnvironmentOverrideKey = "GMAX_GHOSTTY_PANE_SPIKE"

    static func useGhosttyForNewTerminalPanes(userDefaults: UserDefaults = .standard) -> Bool {
        switch ProcessInfo.processInfo.environment[ghosttyEnvironmentOverrideKey] {
            case "1":
                true
            case "0":
                false
            default:
                userDefaults.bool(forKey: useGhosttyForNewTerminalPanesKey)
        }
    }

    static var hasGhosttyEnvironmentOverride: Bool {
        ProcessInfo.processInfo.environment[ghosttyEnvironmentOverrideKey] == "1"
            || ProcessInfo.processInfo.environment[ghosttyEnvironmentOverrideKey] == "0"
    }
}
