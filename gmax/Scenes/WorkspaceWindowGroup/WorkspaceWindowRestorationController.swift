import Combine
import Foundation

@MainActor
final class WorkspaceWindowRestorationController: ObservableObject {
    @Published private(set) var recentlyClosedWindowSceneIdentities: [WorkspaceSceneIdentity] = []

    let initialSceneIdentity: WorkspaceSceneIdentity

    private let userDefaults: UserDefaults
    private var openSceneIdentities: Set<WorkspaceSceneIdentity> = []
    private var launchRestoreSceneIdentities: [WorkspaceSceneIdentity]
    private var hasConsumedPendingLaunchRestoreSceneIdentities = false

    init(
        persistence: WorkspacePersistenceController = .shared,
        userDefaults: UserDefaults = .standard,
    ) {
        self.userDefaults = userDefaults
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
        launchRestoreSceneIdentities = persistedSceneIdentities
        initialSceneIdentity = persistedSceneIdentities.first ?? WorkspaceSceneIdentity()
    }

    init(
        initialSceneIdentity: WorkspaceSceneIdentity,
        pendingLaunchRestoreSceneIdentities: [WorkspaceSceneIdentity],
    ) {
        userDefaults = UserDefaults(suiteName: "WorkspaceWindowRestorationController.\(UUID().uuidString)") ?? .standard
        self.initialSceneIdentity = initialSceneIdentity
        launchRestoreSceneIdentities = [initialSceneIdentity] + pendingLaunchRestoreSceneIdentities
    }

    func markWindowOpen(_ sceneIdentity: WorkspaceSceneIdentity) {
        openSceneIdentities.insert(sceneIdentity)
        if !launchRestoreSceneIdentities.contains(sceneIdentity) {
            launchRestoreSceneIdentities.append(sceneIdentity)
        }
        recentlyClosedWindowSceneIdentities.removeAll { $0 == sceneIdentity }
        persistLaunchRestoreSceneIdentities()
    }

    func recordWindowClosed(_ sceneIdentity: WorkspaceSceneIdentity) {
        openSceneIdentities.remove(sceneIdentity)
        launchRestoreSceneIdentities.removeAll { $0 == sceneIdentity }
        recentlyClosedWindowSceneIdentities.removeAll { $0 == sceneIdentity }
        recentlyClosedWindowSceneIdentities.append(sceneIdentity)
        persistLaunchRestoreSceneIdentities()
    }

    func popMostRecentlyClosedWindow() -> WorkspaceSceneIdentity? {
        recentlyClosedWindowSceneIdentities.popLast()
    }

    func consumePendingLaunchRestoreSceneIdentities() -> [WorkspaceSceneIdentity] {
        guard !hasConsumedPendingLaunchRestoreSceneIdentities else {
            return []
        }

        hasConsumedPendingLaunchRestoreSceneIdentities = true
        return Array(launchRestoreSceneIdentities.dropFirst()).filter { !openSceneIdentities.contains($0) }
    }

    private func persistLaunchRestoreSceneIdentities() {
        userDefaults.set(
            launchRestoreSceneIdentities.map(\.windowID.uuidString),
            forKey: WorkspacePersistenceDefaults.launchRestoreWindowIDsKey,
        )
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
}
