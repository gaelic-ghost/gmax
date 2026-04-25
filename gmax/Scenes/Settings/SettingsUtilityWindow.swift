//
//  SettingsUtilityWindow.swift
//  gmax
//
//  Created by Gale Williams on 4/6/26.
//

import SwiftUI

struct SettingsUtilityWindow: View {
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

    @AppStorage(WorkspacePersistenceDefaults.autoSaveClosedItemsKey)
    private var autoSaveClosedItems = false

    @AppStorage(WorkspacePersistenceDefaults.backgroundSaveIntervalMinutesKey)
    private var backgroundSaveIntervalMinutes = WorkspacePersistenceDefaults.defaultBackgroundSaveIntervalMinutes

    @AppStorage(WorkspacePersistenceDefaults.browserHomePageURLKey)
    private var browserHomePageURL = ""

    var body: some View {
        Form {
            TerminalAppearanceSettingsSection(
                terminalFontName: $terminalFontName,
                terminalFontSize: $terminalFontSize,
                terminalThemeName: $terminalThemeName,
                availableFonts: TerminalAppearance.availableFontOptions(),
                currentAppearance: .init(
                    fontName: terminalFontName,
                    fontSize: max(10, min(terminalFontSize, 28)),
                    theme: TerminalTheme(rawValue: terminalThemeName) ?? .defaultTerminal,
                ),
            )

            WorkspaceSettingsSection(
                restoreWorkspacesOnLaunch: $restoreWorkspacesOnLaunch,
                keepRecentlyClosedWorkspaces: $keepRecentlyClosedWorkspaces,
                autoSaveClosedItems: $autoSaveClosedItems,
                backgroundSaveIntervalMinutes: $backgroundSaveIntervalMinutes,
                browserHomePageURL: $browserHomePageURL,
            )
        }
        .formStyle(.grouped)
        .scenePadding()
        .frame(width: 420)
        .accessibilityIdentifier("settings.utilityWindow")
    }
}

#Preview {
    SettingsUtilityWindow()
}
