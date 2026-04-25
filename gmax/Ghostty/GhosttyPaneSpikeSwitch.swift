//
//  GhosttyPaneSpikeSwitch.swift
//  gmax
//
//  Created by Codex on 4/25/26.
//

import Foundation

enum GhosttyPaneSpikeSwitch {
    static let environmentKey = "GMAX_GHOSTTY_PANE_SPIKE"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }
}
