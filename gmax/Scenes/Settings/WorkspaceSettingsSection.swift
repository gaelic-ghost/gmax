//
//  WorkspaceSettingsSection.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import OSLog
import SwiftUI

struct WorkspaceSettingsSection: View {
    @Binding var restoreWorkspacesOnLaunch: Bool
    @Binding var keepRecentlyClosedWorkspaces: Bool
    @Binding var autoSaveClosedWorkspaces: Bool
    @Binding var backgroundSaveIntervalMinutes: Int

    var body: some View {
        Section("Workspaces") {
            Toggle("Restore workspaces on launch", isOn: $restoreWorkspacesOnLaunch)
                .onChange(of: restoreWorkspacesOnLaunch) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the launch-restoration preference from Settings. Restore workspaces on launch is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
                }

            Toggle("Keep recently closed workspaces", isOn: $keepRecentlyClosedWorkspaces)
                .onChange(of: keepRecentlyClosedWorkspaces) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the recently-closed workspace retention preference from Settings. Keep recently closed workspaces is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
                }

            Toggle("Auto-save closed workspaces", isOn: $autoSaveClosedWorkspaces)
                .onChange(of: autoSaveClosedWorkspaces) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the closed-workspace auto-save preference from Settings. Auto-save closed workspaces is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
                }

            Stepper(value: $backgroundSaveIntervalMinutes, in: 1 ... 60) {
                Text("Background save interval: \(backgroundSaveIntervalMinutes) minute\(backgroundSaveIntervalMinutes == 1 ? "" : "s")")
            }
            .onChange(of: backgroundSaveIntervalMinutes) { _, newValue in
                let normalizedInterval = WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(newValue)
                if normalizedInterval != newValue {
                    backgroundSaveIntervalMinutes = normalizedInterval
                }
                Logger.diagnostics.notice("Updated the background workspace auto-save interval from Settings. Interval: \(normalizedInterval) minute\(normalizedInterval == 1 ? "" : "s", privacy: .public).")
            }

            Text("Restore applies the next time you launch gmax. Recently closed workspaces remain window-local, and they can restore with that window when launch restoration is enabled. Auto-save closed workspaces writes anything you close into the saved-workspace library automatically. Background saves run for each workspace window on the configured interval and also flush immediately during window and app lifecycle changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
