//
//  ExperimentalSettingsSection.swift
//  gmax
//
//  Created by Codex on 4/28/26.
//

import OSLog
import SwiftUI

struct ExperimentalSettingsSection: View {
    @Binding var useGhosttyForNewTerminalPanes: Bool

    var body: some View {
        Section("Experimental") {
            Toggle("Use Ghostty for new terminal panes", isOn: $useGhosttyForNewTerminalPanes)
                .accessibilityIdentifier("settings.experimental.useGhosttyForNewTerminalPanesToggle")
                .onChange(of: useGhosttyForNewTerminalPanes) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the experimental terminal backend preference from Settings. New terminal panes will use \(isEnabled ? "Ghostty" : "SwiftTerm", privacy: .public).")
                }

            Text("Applies to terminal panes created after the setting changes. Existing terminal panes keep their current backend.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if ExperimentalSettingsDefaults.hasGhosttyEnvironmentOverride {
                Text("The GMAX_GHOSTTY_PANE_SPIKE environment override is active for this launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
