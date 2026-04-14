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
			Section("Terminal Font") {
				Picker("Font", selection: $terminalFontName) {
					ForEach(availableFonts) { font in
						Text(font.displayName).tag(font.id)
					}
				}

				VStack(alignment: .leading, spacing: 8) {
					HStack {
						Text("Size")
						Spacer()
						Text("\(Int(terminalFontSize.rounded())) pt")
							.foregroundStyle(.secondary)
					}

					Slider(value: $terminalFontSize, in: 10...28, step: 1)
				}
			}

			Section("Theme") {
				Picker("Theme", selection: $terminalThemeName) {
					ForEach(TerminalTheme.allCases) { theme in
						Text(theme.displayName).tag(theme.rawValue)
					}
				}

				TerminalAppearancePreview(appearance: currentAppearance)
			}

			Section("Workspaces") {
				Toggle("Restore workspaces on launch", isOn: $restoreWorkspacesOnLaunch)
					.onChange(of: restoreWorkspacesOnLaunch) { _, isEnabled in
						diagnosticsLogger.notice("Updated the launch-restoration preference from Settings. Restore workspaces on launch is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
					}

				Toggle("Keep recently closed workspaces", isOn: $keepRecentlyClosedWorkspaces)
					.onChange(of: keepRecentlyClosedWorkspaces) { _, isEnabled in
						diagnosticsLogger.notice("Updated the recently-closed workspace retention preference from Settings. Keep recently closed workspaces is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
						if !isEnabled {
							Task { @MainActor in
								await Task.yield()
								model.clearRecentlyClosedWorkspaces()
							}
						}
					}

				Toggle("Auto-save closed workspaces", isOn: $autoSaveClosedWorkspaces)
					.onChange(of: autoSaveClosedWorkspaces) { _, isEnabled in
						diagnosticsLogger.notice("Updated the closed-workspace auto-save preference from Settings. Auto-save closed workspaces is now \(isEnabled ? "enabled" : "disabled", privacy: .public).")
					}

				Text("Restore applies the next time you launch gmax. Recently closed workspaces stay in-memory only for this running session. Auto-save closed workspaces sends anything you close into the saved workspace library automatically.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
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
}

private struct TerminalAppearancePreview: View {
	let appearance: TerminalAppearance

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("$ pwd")
			Text("~/Workspace/gmax")
			Text("$ swift build")
			Text("Build complete! Nerd glyphs: \u{e0b6} \u{f115} \u{f0e7}")
		}
		.font(Font(appearance.resolvedFont))
		.foregroundStyle(Color(nsColor: appearance.theme.foregroundColor))
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.background(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.fill(Color(nsColor: appearance.theme.backgroundColor))
		)
		.overlay(
			RoundedRectangle(cornerRadius: 12, style: .continuous)
				.stroke(Color(nsColor: appearance.theme.cursorColor).opacity(0.35), lineWidth: 1)
		)
	}
}

#Preview {
	SettingsUtilityWindow(model: ShellModel())
}
