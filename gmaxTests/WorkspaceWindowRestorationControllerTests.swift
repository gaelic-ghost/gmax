import Foundation
import Testing
@testable import gmax

@MainActor
struct WorkspaceWindowRestorationControllerTests {
    @Test func `launch restore prefers the stored last session window identities`() {
        let userDefaultsSuiteName = "WorkspaceWindowRestorationControllerTests.launch-restore"
        let userDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: userDefaultsSuiteName)
        let persistence = WorkspacePersistenceController.inMemoryForTesting()
        let first = WorkspaceSceneIdentity()
        let second = WorkspaceSceneIdentity()

        let firstStore = WorkspaceStore(
            sceneIdentity: first,
            workspaces: [TestSupport.makeWorkspace(title: "First Window")],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )
        let secondStore = WorkspaceStore(
            sceneIdentity: second,
            workspaces: [TestSupport.makeWorkspace(title: "Second Window")],
            persistence: persistence,
            launchContextBuilder: TestSupport.makeLaunchContextBuilder(defaultCurrentDirectory: "/tmp/gmax-tests"),
        )

        firstStore.persistSceneStateNow(reason: .unitTestImmediateFlush)
        secondStore.persistSceneStateNow(reason: .unitTestImmediateFlush)
        userDefaults.set(
            [first.windowID.uuidString, second.windowID.uuidString],
            forKey: WorkspacePersistenceDefaults.launchRestoreWindowIDsKey,
        )

        let controller = WorkspaceWindowRestorationController(
            persistence: persistence,
            userDefaults: userDefaults,
        )

        #expect(controller.initialSceneIdentity == first)
        #expect(controller.consumePendingLaunchRestoreSceneIdentities() == [second])
    }

    @Test func `reopening a window removes it from the recently closed stack`() {
        let first = WorkspaceSceneIdentity()
        let second = WorkspaceSceneIdentity()
        let controller = WorkspaceWindowRestorationController(
            initialSceneIdentity: first,
            pendingLaunchRestoreSceneIdentities: [],
        )

        controller.recordWindowClosed(first)
        controller.recordWindowClosed(second)
        controller.markWindowOpen(first)

        #expect(controller.recentlyClosedWindowSceneIdentities == [second])
    }

    @Test func `popMostRecentlyClosedWindow returns the newest closed identity`() {
        let first = WorkspaceSceneIdentity()
        let second = WorkspaceSceneIdentity()
        let controller = WorkspaceWindowRestorationController(
            initialSceneIdentity: first,
            pendingLaunchRestoreSceneIdentities: [],
        )

        controller.recordWindowClosed(first)
        controller.recordWindowClosed(second)

        #expect(controller.popMostRecentlyClosedWindow() == second)
        #expect(controller.recentlyClosedWindowSceneIdentities == [first])
    }

    @Test func `launch restore uses the first persisted identity as the initial window`() {
        let first = WorkspaceSceneIdentity()
        let second = WorkspaceSceneIdentity()
        let controller = WorkspaceWindowRestorationController(
            initialSceneIdentity: first,
            pendingLaunchRestoreSceneIdentities: [second],
        )

        #expect(controller.initialSceneIdentity == first)
        #expect(controller.consumePendingLaunchRestoreSceneIdentities() == [second])
    }

    @Test func `marking a restored window open removes it from the pending launch restore queue`() {
        let first = WorkspaceSceneIdentity()
        let second = WorkspaceSceneIdentity()
        let controller = WorkspaceWindowRestorationController(
            initialSceneIdentity: first,
            pendingLaunchRestoreSceneIdentities: [second],
        )

        controller.markWindowOpen(second)

        #expect(controller.consumePendingLaunchRestoreSceneIdentities().isEmpty)
    }
}
