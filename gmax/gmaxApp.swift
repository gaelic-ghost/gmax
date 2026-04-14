//
//  gmaxApp.swift
//  gmax
//
//  Created by Gale Williams on 3/13/26.
//

import SwiftUI

enum AppWindowRole: String {
	case mainShell
	case settings
}

@main
struct gmaxApp: App {
	@StateObject var shellModel: ShellModel
	@State var selectedWorkspaceID: WorkspaceID?
	@State var isBypassingLastPaneCloseConfirmation = false
	@State var isSavedWorkspaceLibraryPresented = false

	init() {
		WorkspacePersistenceDefaults.registerDefaults()
		let shellModel = ShellModel()
		_shellModel = StateObject(wrappedValue: shellModel)
		_selectedWorkspaceID = State(initialValue: shellModel.normalizedWorkspaceSelection(nil))
	}

	var body: some Scene {
		Window("gmax exploration", id: "main-window") {
			MainShellSceneView(
				shellModel: shellModel,
				selectedWorkspaceID: $selectedWorkspaceID,
				isBypassingLastPaneCloseConfirmation: $isBypassingLastPaneCloseConfirmation,
				isSavedWorkspaceLibraryPresented: $isSavedWorkspaceLibraryPresented
			)
		}
		.defaultSize(width: 1_440, height: 900)
		.commands {
			MainShellCommands(
				shellModel: shellModel,
				selectedWorkspaceID: $selectedWorkspaceID,
				isSavedWorkspaceLibraryPresented: $isSavedWorkspaceLibraryPresented,
				selectedWorkspace: selectedWorkspace,
				canDeleteSelectedWorkspace: canDeleteSelectedWorkspace,
				canCloseWorkspace: canCloseWorkspace,
				canCloseWorkspaceToLibrary: canCloseWorkspaceToLibrary,
				saveSelectedWorkspace: saveSelectedWorkspace,
				performContextualClose: performContextualClose,
				performWorkspaceClose: performWorkspaceClose,
				performWindowClose: performWindowClose,
				presentWorkspaceRename: presentWorkspaceRename
			)
		}

		Settings {
			SettingsUtilityWindow(model: shellModel)
				.windowRole(.settings)
		}
	}
}

extension Notification.Name {
	static let presentWorkspaceRenameSheet = Notification.Name("gmax.presentWorkspaceRenameSheet")
}
