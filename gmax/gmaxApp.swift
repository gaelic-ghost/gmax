import SwiftUI

@main
struct gmaxApp: App {
    @StateObject private var windowRestoration = WorkspaceWindowRestorationController()

    init() {
        UITestLaunchBehavior.resetStateIfNeeded()
    }

    var body: some Scene {
        WindowGroup(
            "gmax Window",
            id: "main-window",
            for: WorkspaceSceneIdentity.self,
        ) { sceneIdentity in
            WorkspaceWindowSceneView(
                sceneIdentity: sceneIdentity.wrappedValue,
                windowRestoration: windowRestoration,
            )
        } defaultValue: {
            windowRestoration.nextDefaultSceneIdentity()
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(UITestLaunchBehavior.isEnabled ? .disabled : .automatic)
        .defaultSize(width: 1440, height: 900)
        .commands {
            WorkspaceWindowSceneCommands(windowRestoration: windowRestoration)
        }

        Settings {
            SettingsUtilityWindow()
        }
    }
}
