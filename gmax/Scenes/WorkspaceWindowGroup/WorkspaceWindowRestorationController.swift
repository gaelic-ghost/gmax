import Combine
import Foundation

@MainActor
final class WorkspaceWindowRestorationController: ObservableObject {
    @Published private(set) var recentlyClosedWindowSceneIdentities: [WorkspaceSceneIdentity] = []

    let initialSceneIdentity: WorkspaceSceneIdentity

    private let persistence: WorkspacePersistenceController
    private var openSceneIdentities: Set<WorkspaceSceneIdentity> = []
    private var launchRestoreSceneIdentities: [WorkspaceSceneIdentity]
    private var hasConsumedPendingLaunchRestoreSceneIdentities = false
    private var isApplicationTerminating = false

    init(
        persistence: WorkspacePersistenceController = .shared,
        userDefaults: UserDefaults = .standard,
    ) {
        self.persistence = persistence
        let shouldRestore = WorkspacePersistenceDefaults.restoreWorkspacesOnLaunch(userDefaults: userDefaults)
        let preferredSceneIdentities = Self.storedLaunchRestoreSceneIdentities(userDefaults: userDefaults)
        let persistedSceneIdentities: [WorkspaceSceneIdentity] = if shouldRestore {
            if preferredSceneIdentities.isEmpty {
                persistence.loadLiveSceneIdentities()
            } else {
                persistence.loadLiveSceneIdentities(matching: preferredSceneIdentities)
            }
        } else {
            []
        }
        recentlyClosedWindowSceneIdentities = persistence.loadRecentlyClosedWindowSceneIdentities()
        launchRestoreSceneIdentities = persistedSceneIdentities
        initialSceneIdentity = persistedSceneIdentities.first ?? WorkspaceSceneIdentity()
    }

    init(
        initialSceneIdentity: WorkspaceSceneIdentity,
        pendingLaunchRestoreSceneIdentities: [WorkspaceSceneIdentity],
    ) {
        persistence = .inMemoryForTesting()
        self.initialSceneIdentity = initialSceneIdentity
        launchRestoreSceneIdentities = [initialSceneIdentity] + pendingLaunchRestoreSceneIdentities
    }

    private static func storedLaunchRestoreSceneIdentities(
        userDefaults: UserDefaults,
    ) -> [WorkspaceSceneIdentity] {
        guard let rawWindowIDs = userDefaults.array(forKey: WorkspacePersistenceDefaults.launchRestoreWindowIDsKey) as? [String] else {
            return []
        }

        return rawWindowIDs.compactMap { rawWindowID in
            UUID(uuidString: rawWindowID).map { WorkspaceSceneIdentity(windowID: $0) }
        }
    }

    func markWindowOpen(_ sceneIdentity: WorkspaceSceneIdentity) {
        isApplicationTerminating = false
        openSceneIdentities.insert(sceneIdentity)
        if !launchRestoreSceneIdentities.contains(sceneIdentity) {
            launchRestoreSceneIdentities.append(sceneIdentity)
        }
        persistence.markWindowOpen(sceneIdentity)
        recentlyClosedWindowSceneIdentities = persistence.loadRecentlyClosedWindowSceneIdentities()
    }

    func recordWindowClosed(_ sceneIdentity: WorkspaceSceneIdentity) {
        guard !isApplicationTerminating else {
            openSceneIdentities.remove(sceneIdentity)
            return
        }

        openSceneIdentities.remove(sceneIdentity)
        launchRestoreSceneIdentities.removeAll { $0 == sceneIdentity }
        persistence.markWindowClosed(sceneIdentity)
        recentlyClosedWindowSceneIdentities = persistence.loadRecentlyClosedWindowSceneIdentities()
    }

    func popMostRecentlyClosedWindow() -> WorkspaceSceneIdentity? {
        guard let sceneIdentity = recentlyClosedWindowSceneIdentities.first else {
            return nil
        }

        recentlyClosedWindowSceneIdentities = Array(recentlyClosedWindowSceneIdentities.dropFirst())
        return sceneIdentity
    }

    func noteApplicationWillTerminate() {
        isApplicationTerminating = true
    }

    func consumePendingLaunchRestoreSceneIdentities() -> [WorkspaceSceneIdentity] {
        guard !hasConsumedPendingLaunchRestoreSceneIdentities else {
            return []
        }

        hasConsumedPendingLaunchRestoreSceneIdentities = true
        return Array(launchRestoreSceneIdentities.dropFirst()).filter { !openSceneIdentities.contains($0) }
    }
}
