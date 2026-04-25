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
    @Binding var browserHomePageURL: String

    var body: some View {
        Section("Workspaces") {
            Toggle("Restore workspaces on launch", isOn: $restoreWorkspacesOnLaunch)
                .accessibilityIdentifier("settings.workspace.restoreOnLaunchToggle")
                .onChange(of: restoreWorkspacesOnLaunch) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the launch-restoration preference from Settings. Restore workspaces on launch is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
                }

            Toggle("Keep recently closed workspaces", isOn: $keepRecentlyClosedWorkspaces)
                .accessibilityIdentifier("settings.workspace.keepRecentlyClosedToggle")
                .onChange(of: keepRecentlyClosedWorkspaces) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the recently-closed workspace retention preference from Settings. Keep recently closed workspaces is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
                }

            Toggle("Auto-save closed workspaces and windows", isOn: $autoSaveClosedItems)
                .accessibilityIdentifier("settings.workspace.autoSaveClosedItemsToggle")
                .onChange(of: autoSaveClosedItems) { _, isEnabled in
                    Logger.diagnostics.notice("Updated the closed-item auto-save preference from Settings. Auto-save closed workspaces and windows is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
                }

            Stepper(value: $backgroundSaveIntervalMinutes, in: 1...60) {
                Text("Background save interval: \(backgroundSaveIntervalMinutes) minute\(backgroundSaveIntervalMinutes == 1 ? "" : "s")")
            }
            .accessibilityIdentifier("settings.workspace.backgroundSaveIntervalStepper")
            .onChange(of: backgroundSaveIntervalMinutes) { _, newValue in
                let normalizedInterval = WorkspacePersistenceDefaults.normalizedBackgroundSaveIntervalMinutes(newValue)
                if normalizedInterval != newValue {
                    backgroundSaveIntervalMinutes = normalizedInterval
                }
                Logger.diagnostics.notice("Updated the background workspace auto-save interval from Settings. Interval: \(normalizedInterval) minute\(normalizedInterval == 1 ? "" : "s", privacy: .public).")
            }

            TextField(
                "Browser home URL",
                text: $browserHomePageURL,
                prompt: Text("about:blank when empty"),
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("settings.workspace.browserHomeURLField")
            .onChange(of: browserHomePageURL) { _, newValue in
                let normalizedValue = BrowserNavigationDefaults.normalizedNavigationURLString(from: newValue) ?? ""
                if normalizedValue != newValue {
                    browserHomePageURL = normalizedValue
                }
                Logger.diagnostics.notice("Updated the browser home page preference from Settings. Browser home URL is now \(normalizedValue.isEmpty ? "empty (about:blank)" : normalizedValue, privacy: .public).")
            }

            Text("Restore applies the next time you launch gmax. Recently closed workspaces remain window-local, and they can restore with that window when launch restoration is enabled. Auto-save writes closed workspaces and closed windows into the library automatically. When it is off, you can still archive them explicitly with the library-specific close commands. Background saves run for each workspace window on the configured interval and also flush immediately during window and app lifecycle changes. When the browser home URL is empty, new browser panes start on about:blank.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
