//
//  gmaxApp.swift
//  gmax
//
//  Created by Gale Williams on 3/13/26.
//

import OSLog
import SwiftUI

@main
struct gmaxApp: App {
	init() {
		UITestLaunchBehavior.resetStateIfNeeded()
	}

	var body: some Scene {
		WindowGroup("gmax exploration", id: "main-window") {
			MainShellWindowView()
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
