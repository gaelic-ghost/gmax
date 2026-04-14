//
//  SettingsUtilityWindow.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import AppKit
import OSLog
import SwiftUI

struct SettingsUtilityWindow: View {
	@ObservedObject var model: ShellModel
	private let diagnosticsLogger = Logger.gmax(.diagnostics)

	@AppStorage(TerminalAppearanceDefaults.fontNameKey)
	private var terminalFontName = TerminalAppearance.fallback.fontName

	@AppStorage(TerminalAppearanceDefaults.fontSizeKey)
	private var terminalFontSize = TerminalAppearanceDefaults.defaultFontSize

	@AppStorage(TerminalAppearanceDefaults.themeKey)
	private var terminalThemeName = TerminalTheme.defaultTerminal.rawValue

	@AppStorage(WorkspacePersistenceDefaults.restoreWorkspacesOnLaunchKey)
	private var restoreWorkspacesOnLaunch = WorkspacePersistenceDefaults.systemRestoresWindowsByDefault()

	@AppStorage(WorkspacePersistenceDefaults.keepRecentlyClosedWorkspacesKey)
	private var keepRecentlyClosedWorkspaces = true

	@AppStorage(WorkspacePersistenceDefaults.autoSaveClosedWorkspacesKey)
	private var autoSaveClosedWorkspaces = false

	private let availableFonts = TerminalAppearance.availableFontOptions()

	var body: some View {
		Form {
			TerminalAppearanceSettingsSection(
				terminalFontName: $terminalFontName,
				terminalFontSize: $terminalFontSize,
				terminalThemeName: $terminalThemeName,
				availableFonts: availableFonts,
				currentAppearance: currentAppearance
			)

			WorkspaceSettingsSection(
				restoreWorkspacesOnLaunch: $restoreWorkspacesOnLaunch,
				keepRecentlyClosedWorkspaces: $keepRecentlyClosedWorkspaces,
				autoSaveClosedWorkspaces: $autoSaveClosedWorkspaces,
				onRestoreWorkspacesOnLaunchChanged: handleRestoreWorkspacesOnLaunchChanged,
				onKeepRecentlyClosedWorkspacesChanged: handleKeepRecentlyClosedWorkspacesChanged,
				onAutoSaveClosedWorkspacesChanged: handleAutoSaveClosedWorkspacesChanged
			)
		}
		.formStyle(.grouped)
		.scenePadding()
		.frame(width: 420)
	}

	private var currentAppearance: TerminalAppearance {
		TerminalAppearance.persisted(
			fontName: terminalFontName,
			fontSize: terminalFontSize,
			themeName: terminalThemeName
		)
	}

	private func handleRestoreWorkspacesOnLaunchChanged(_ isEnabled: Bool) {
		diagnosticsLogger.notice("Updated the launch-restoration preference from Settings. Restore workspaces on launch is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
	}

	private func handleKeepRecentlyClosedWorkspacesChanged(_ isEnabled: Bool) {
		diagnosticsLogger.notice("Updated the recently-closed workspace retention preference from Settings. Keep recently closed workspaces is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
		if !isEnabled {
			Task { @MainActor in
				await Task.yield()
				model.clearRecentlyClosedWorkspaces()
			}
		}
	}

	private func handleAutoSaveClosedWorkspacesChanged(_ isEnabled: Bool) {
		diagnosticsLogger.notice("Updated the closed-workspace auto-save preference from Settings. Auto-save closed workspaces is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
	}
}

#Preview {
	SettingsUtilityWindow(model: ShellModel())
}
