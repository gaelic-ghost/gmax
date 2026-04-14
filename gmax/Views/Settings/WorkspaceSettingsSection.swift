//
//  WorkspaceSettingsSection.swift
//  gmax
//
//  Created by Gale Williams on 4/14/26.
//

import SwiftUI

struct WorkspaceSettingsSection: View {
	@Binding var restoreWorkspacesOnLaunch: Bool
	@Binding var keepRecentlyClosedWorkspaces: Bool
	@Binding var autoSaveClosedWorkspaces: Bool

	let onRestoreWorkspacesOnLaunchChanged: (Bool) -> Void
	let onKeepRecentlyClosedWorkspacesChanged: (Bool) -> Void
	let onAutoSaveClosedWorkspacesChanged: (Bool) -> Void

	var body: some View {
		Section("Workspaces") {
			Toggle("Restore workspaces on launch", isOn: $restoreWorkspacesOnLaunch)
				.onChange(of: restoreWorkspacesOnLaunch) { _, isEnabled in
					onRestoreWorkspacesOnLaunchChanged(isEnabled)
				}

			Toggle("Keep recently closed workspaces", isOn: $keepRecentlyClosedWorkspaces)
				.onChange(of: keepRecentlyClosedWorkspaces) { _, isEnabled in
					onKeepRecentlyClosedWorkspacesChanged(isEnabled)
				}

			Toggle("Auto-save closed workspaces", isOn: $autoSaveClosedWorkspaces)
				.onChange(of: autoSaveClosedWorkspaces) { _, isEnabled in
					onAutoSaveClosedWorkspacesChanged(isEnabled)
				}

			Text("Restore applies the next time you launch gmax. Recently closed workspaces stay in memory only for the current app session. Auto-save closed workspaces writes anything you close into the saved-workspace library automatically.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}
}
