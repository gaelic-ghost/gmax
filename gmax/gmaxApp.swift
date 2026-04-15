//
//  gmaxApp.swift
//  gmax
//
//  Created by Gale Williams on 3/13/26.
//

import SwiftUI

@main
struct gmaxApp: App {
	init() {
		UITestLaunchBehavior.applyIfNeeded()
		WorkspacePersistenceDefaults.registerDefaults()
	}

	var body: some Scene {
		WindowGroup("gmax exploration", id: "main-window") {
			MainShellSceneView()
		}
		.defaultLaunchBehavior(.presented)
		.restorationBehavior(UITestLaunchBehavior.isEnabled ? .disabled : .automatic)
		.defaultSize(width: 1_440, height: 900)
		.commands {
			MainShellCommands()
		}

		Settings {
			SettingsUtilityWindow()
		}
	}
}
