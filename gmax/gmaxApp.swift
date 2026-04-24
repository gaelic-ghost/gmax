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
        .defaultSize(width: 1240, height: 780)
        .keyboardShortcut(.init("n", modifiers: [.command, .shift]))
        .commands {
            WorkspaceWindowSceneCommands(windowRestoration: windowRestoration)
        }

        Settings {
            SettingsUtilityWindow()
        }
    }
}
