/*
 WorkspacePersistenceProfile defines which persistent store configuration the
 app should use for a given runtime. It keeps production, debug, UI-test, and
 in-memory testing stores explicit so persistence behavior is intentional
 instead of being inferred from scattered ad hoc branches.
 */

import Foundation

protocol ProcessInfoReading {
    nonisolated var environment: [String: String] { get }
}

extension ProcessInfo: ProcessInfoReading {}

enum WorkspacePersistenceProfile: String {
    case productionOnDisk = "production"
    case debugOnDisk = "debug"
    case uiTestOnDisk = "ui-test"
    case inMemory = "in-memory"

    nonisolated static let environmentKey = "GMAX_PERSISTENCE_PROFILE"
    nonisolated static let uiTestResetStateEnvironmentKey = "GMAX_UI_TEST_RESET_STATE"
    nonisolated static let xCTestConfigurationFilePathEnvironmentKey = "XCTestConfigurationFilePath"

    nonisolated var usesInMemoryStore: Bool {
        self == .inMemory
    }

    nonisolated var storeFileName: String? {
        switch self {
            case .productionOnDisk:
                "WorkspaceStore.sqlite"
            case .debugOnDisk:
                "WorkspaceStore.debug.sqlite"
            case .uiTestOnDisk:
                "WorkspaceStore.ui-test.sqlite"
            case .inMemory:
                nil
        }
    }

    nonisolated var contextName: String {
        switch self {
            case .productionOnDisk:
                "WorkspacePersistence.productionViewContext"
            case .debugOnDisk:
                "WorkspacePersistence.debugViewContext"
            case .uiTestOnDisk:
                "WorkspacePersistence.uiTestViewContext"
            case .inMemory:
                "WorkspacePersistence.inMemoryViewContext"
        }
    }

    nonisolated var displayName: String {
        switch self {
            case .productionOnDisk:
                "production on-disk workspace store"
            case .debugOnDisk:
                "debug on-disk workspace store"
            case .uiTestOnDisk:
                "UI-test on-disk workspace store"
            case .inMemory:
                "in-memory workspace store"
        }
    }

    nonisolated static func appDefault(processInfo: ProcessInfoReading = ProcessInfo.processInfo) -> WorkspacePersistenceProfile {
        if let requestedProfile = processInfo.environment[environmentKey] {
            if let explicitProfile = WorkspacePersistenceProfile(rawValue: requestedProfile) {
                return explicitProfile
            }
        }

        if processInfo.environment[uiTestResetStateEnvironmentKey] == "1" {
            return .uiTestOnDisk
        }

        if processInfo.environment[xCTestConfigurationFilePathEnvironmentKey] != nil {
            return .inMemory
        }

#if DEBUG
        return .debugOnDisk
#else
        return .productionOnDisk
#endif
    }
}
