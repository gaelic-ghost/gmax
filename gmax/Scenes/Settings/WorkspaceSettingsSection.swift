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
    @Binding var autoSaveClosedItems: Bool
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

            Toggle("Auto-save closed workspaces and windows", isOn: $autoSaveClosedItems)
                .onChange(of: autoSaveClosedItems) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the closed-item auto-save preference from Settings. Auto-save closed workspaces and windows is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
                }

            Stepper(value: $backgroundSaveIntervalMinutes, in: 1...60) {
                Text("Background save interval: \(backgroundSaveIntervalMinutes) minute\(backgroundSaveIntervalMinutes == 1 ? "" : "s")")
            }
            .onChange(of: backgroundSaveIntervalMinutes) { _, newValue in
                let normalizedInterval = WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(newValue)
                if normalizedInterval != newValue {
                    backgroundSaveIntervalMinutes = normalizedInterval
                }
                Logger.diagnostics.notice("Updated the background workspace auto-save interval from Settings. Interval: \(normalizedInterval) minute\(normalizedInterval == 1 ? "" : "s", privacy: .public).")
            }

            Text("Restore applies the next time you launch gmax. Recently closed workspaces remain window-local, and they can restore with that window when launch restoration is enabled. Auto-save writes closed workspaces and closed windows into the library automatically. When it is off, you can still archive them explicitly with the library-specific close commands. Background saves run for each workspace window on the configured interval and also flush immediately during window and app lifecycle changes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
