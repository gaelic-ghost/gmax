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

	init() {
		UITestLaunchBehavior.applyIfNeeded()
		WorkspacePersistenceDefaults.registerDefaults()
		let shellModel = ShellModel()
		_shellModel = StateObject(wrappedValue: shellModel)
	}

	var body: some Scene {
		WindowGroup("gmax exploration", id: "main-window") {
			MainShellSceneView(shellModel: shellModel)
		}
		.defaultLaunchBehavior(.presented)
		.restorationBehavior(UITestLaunchBehavior.isEnabled ? .disabled : .automatic)
		.defaultSize(width: 1_440, height: 900)
		.commands {
			MainShellCommands()
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
