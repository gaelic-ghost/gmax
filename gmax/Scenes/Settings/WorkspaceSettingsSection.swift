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

            Text("Restore applies the next time you launch gmax. Recently closed workspaces stay in memory only for the current app session. Auto-save closed workspaces writes anything you close into the saved-workspace library automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
