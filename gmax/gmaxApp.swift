import SwiftUI

@main
struct gmaxApp: App {
	init() {
		UITestLaunchBehavior.resetStateIfNeeded()
	}

	var body: some Scene {
		WindowGroup(
			"gmax exploration",
			id: "main-window",
			for: WorkspaceSceneIdentity.self
		) { sceneIdentity in
			WorkspaceWindowSceneView(sceneIdentity: sceneIdentity.wrappedValue)
		} defaultValue: {
			WorkspaceSceneIdentity()
		}
		.defaultLaunchBehavior(.presented)
		.restorationBehavior(UITestLaunchBehavior.isEnabled ? .disabled : .automatic)
		.defaultSize(width: 1_440, height: 900)
		.commands {
			WorkspaceWindowSceneCommands()
		}

		Settings {
			SettingsUtilityWindow()
		}
	}
}
